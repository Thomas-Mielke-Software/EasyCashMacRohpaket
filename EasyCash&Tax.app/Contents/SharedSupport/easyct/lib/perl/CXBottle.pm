# (c) Copyright 2005-2011. CodeWeavers, Inc.
package CXBottle;
use strict;

use CXLog;
use CXUtils;


sub set_environment($$)
{
    my ($cxconfig, $msg)=@_;
    my $userenv = $cxconfig->get_section("EnvironmentVariables");
    if (defined $userenv)
    {
        my $traced;
        foreach my $var (@{$userenv->get_field_list()})
        {
            if (!$traced)
            {
                cxlog("$msg:\n");
                $traced=1;
            }
            if ($var =~ /^(?:CX_BOTTLE|WINEPREFIX)$/)
            {
                cxerr("setting '$var' in an [EnvironmentVariables] section is not allowed\n");
                exit 1;
            }
            my $value=$userenv->get($var);
            $ENV{$var}=expand_string($value);
            if ($var =~ /^CX_(?:MANAGED_)?BOTTLE_PATH$/ and
                $ENV{$var} =~ m%(?:^[^/]|:[^/])%)
            {
                cxerr("'$var' must contain absolute paths\n");
                exit 1;
            }
            cxlog(" $var -> $ENV{$var}\n");
        }
    }
}

sub get_managed_bottle_dir()
{
    return "$ENV{CX_ROOT}/support";
}

my $user_dir;
sub get_user_dir()
{
    if (!defined $user_dir and defined $ENV{HOME} and -o $ENV{HOME})
    {
        my $productname=CXUtils::get_product_name();
        $user_dir="$ENV{HOME}/Library/Application Support/$productname";
    }
    return $user_dir;
}

sub get_user_bottle_dir()
{
    my $user_dir=get_user_dir();
    return "$user_dir/Bottles" if (defined $user_dir);
    return undef;
}

# Returns the path of the configuration file to use to save CrossOver settings.
sub get_rw_config_filename()
{
    my $productid=CXUtils::get_product_id();
    my $filename=get_user_dir() . "/$productid.conf";
    return $filename;
}

# Locks the CrossOver configuration file and then loads it.
# To avoid races when changing the configuration file it is necessary to
# follow these rules:
# - The data returned by a get_crossover_config() call made prior to
#   lock_and_get_rw_config() must not be trusted. This is because the
#   configuration file was not yet locked and thus may have changed between
#   the two calls.
# - The data returned by lock_and_get_rw_config() must not be trusted. This
#   is because the CXRWConfig object does not aggregate the data from all the
#   configuration files. So it is missing any setting not present in the file
#   where we save modifications.
# - So the proper way to test the value of a setting and then modify it
#   race-free is:
#       my ($cxrwconfig, $lock)=CXBottle::lock_and_get_rw_config();
#       my $cxconfig=CXBottle::get_crossover_config();
#       if ($cxconfig->get('section', 'field') ...)
#       {
#           $cxrwconfig->set('section', 'field', ...);
#       }
#       $cxrwconfig->save();
#       CXUtils::cxunlock($lock);
#       $cxrwconfig=undef;       # Should not be reused once unlocked
#       $cxconfig=undef;         # Does not contain the modified setting
sub lock_and_get_rw_config()
{
    my $filename=get_rw_config_filename();
    my $lock=CXUtils::cxlock(cxbasename($filename));
    if (!defined $lock)
    {
        cxwarn("$@\n");
        cxwarn("locking failed, continuing without a lock\n");
    }
    require CXRWConfig;
    # Make sure we get a fresh copy from the now locked file
    CXRWConfig::uncache_file($filename);
    my $cxrwconfig=CXRWConfig->new($filename);
    return ($cxrwconfig, $lock);
}

# Reads all the bottle-independent configuration files
# and sets up the corresponding environment variables.
sub get_crossover_config()
{
    # Set to the default values so they can be used in [EnvironmentVariables]
    $ENV{CX_BOTTLE_PATH} ||= get_user_bottle_dir() || "";
    $ENV{CX_MANAGED_BOTTLE_PATH} ||= get_managed_bottle_dir();

    require CXConfig;
    my $productid=CXUtils::get_product_id();
    my $cxconfig=CXConfig->new("$ENV{CX_ROOT}/etc/$productid.conf");
    set_environment($cxconfig, "Global environment variables");
    my $user_dir=get_user_dir();
    if (defined $user_dir)
    {
        $cxconfig->read("$user_dir/$productid.conf");
        set_environment($cxconfig, "User environment variables");
    }
    return $cxconfig;
}

sub is_initialized()
{
    return ($ENV{CX_INITIALIZED} || "") eq "$>:$ENV{CX_BOTTLE}";
}

sub compute_new_wineprefix($$)
{
    my ($bottle, $scope)=@_;
    my $path;

    if ($scope eq "private")
    {
        return $bottle if ($bottle =~ m%^/%);
        $path=$ENV{CX_BOTTLE_PATH};
    }
    else
    {
        # We don't allow absolute paths for managed bottles because they are
        # incompatible with the managed/stub duality
        $path=$ENV{CX_MANAGED_BOTTLE_PATH};
    }
    if ($bottle =~ m%/%)
    {
        $@=cxgettext("invalid '\%s' bottle name", $bottle);
        return undef;
    }
    foreach my $dir (split /:+/, $path)
    {
        next if ($dir eq "");
        my $d=$dir;
        while (!-e $d)
        {
            $d=cxdirname($d);
        }
        return "$dir/$bottle" if (-d $d and -w _);
    }
    $@=cxgettext("found no writable directory in '\%s'", $path);
    return undef;
}

sub find_bottle($$)
{
    my ($bottle, $scope)=@_;
    my $path;

    if ($scope eq "private")
    {
        return $bottle if ($bottle =~ m%^/%);
        $path=$ENV{CX_BOTTLE_PATH};
    }
    else
    {
        # We don't allow absolute paths for managed bottles because they are
        # incompatible with the managed/stub duality
        $path=$ENV{CX_MANAGED_BOTTLE_PATH};
    }
    if ($bottle =~ m%/%)
    {
        $@=cxgettext("invalid '\%s' bottle name", $bottle);
        return undef;
    }
    foreach my $dir (split /:+/, $path)
    {
        next if ($dir eq "");
        return "$dir/$bottle" if (-f "$dir/$bottle/system.reg");
    }
    $@=cxgettext("bottle '\%1\$s' not found in '\%2\$s'", $bottle, $path);
    return undef;
}

sub is_wineprefix_valid($;$)
{
    my ($wineprefix, $minimal_checks)=@_;

    $@="";
    if (!defined $wineprefix)
    {
        $@=cxgettext("'\%s' bottle not found", $ENV{CX_BOTTLE});
    }
    elsif (!-d $wineprefix)
    {
        $@=cxgettext("'\%s' is not a directory", $wineprefix);
    }
    elsif ($> == 0 and !-o _ and !$minimal_checks)
    {
        $@=cxgettext("'\%s' does not belong to root", $wineprefix);
    }
    elsif (!-r _)
    {
        $@=cxgettext("'\%s' is not readable", $wineprefix);
    }
    elsif (!-w _ and !$minimal_checks)
    {
        $@=cxgettext("'\%s' is not writable", $wineprefix);
    }
    if ($@)
    {
        $@=cxgettext("invalid '\%1\$s' bottle: \%2\$s\n", $ENV{CX_BOTTLE}, $@);
        return 0;
    }
    return 1;
}

sub setup_bottle_wineprefix($)
{
    my ($scope)=@_;

    my ($raw_wineprefix, $private_err, $managed_err);
    if (($scope || "private") eq "private")
    {
        $raw_wineprefix=CXBottle::find_bottle($ENV{CX_BOTTLE}, "private");
        $scope="private" if (defined $raw_wineprefix);
        $private_err=$@;
    }
    if (!defined $raw_wineprefix and ($scope || "managed") eq "managed")
    {
        $raw_wineprefix=CXBottle::find_bottle($ENV{CX_BOTTLE}, "managed");
        $scope="managed" if (defined $raw_wineprefix);
        $managed_err=$@;
    }
    if (!defined $raw_wineprefix)
    {
        $@=cxgettext("Unable to find the '\%s' bottle:\n", $ENV{CX_BOTTLE});
        $@.="$private_err\n" if (defined $private_err);
        $@.="$managed_err\n" if (defined $managed_err);
        return undef;
    }

    if ($ENV{CX_BOTTLE} eq "default")
    {
        # Get the default bottle's real name so that this is what
        # gets used to identify it (e.g. in menus).
        my $target=readlink($raw_wineprefix);
        if (defined $target)
        {
            $ENV{CX_BOTTLE}=cxbasename($target);
        }

        # Set $@ so the caller can issue a warning if he deems it appropriate
        $@=cxgettext("Using the default (\%s) bottle.\n", $ENV{CX_BOTTLE});
    }
    else
    {
        $@=undef;
    }

    # Completely dereference wineprefix so further accesses skip all symbolic
    # links (especially those pointing from a network drive to a local one).
    $ENV{WINEPREFIX}=CXUtils::cxrealpath($raw_wineprefix);

    # Do minimal checks on the wineprefix. We cannot do more checks because
    # we don't know what the caller wants to do with it. If it's a managed
    # bottle he may decide to replicate it to a stub bottle for instance.
    if (!is_wineprefix_valid($ENV{WINEPREFIX}, 1))
    {
        $@=cxgettext("'\%s' is not a directory", $ENV{WINEPREFIX});
        $@=cxgettext("invalid '\%1\$s' bottle: \%2\$s\n", $ENV{CX_BOTTLE}, $@);
        return undef;
    }
    return ($scope, $raw_wineprefix);
}

sub get_bottle_lock_prefix($)
{
    my ($wineprefix)=@_;
    return "bottle-" . CXUtils::get_wine_dir_id($wineprefix);
}

sub unlock_bottle($)
{
    my ($lock)=@_;
    if (defined $ENV{CX_BOTTLE_LOCKED})
    {
        $ENV{CX_BOTTLE_LOCKED} =~ s/<\Q$lock->{name}\E>//;
        delete $ENV{CX_BOTTLE_LOCKED} if ($ENV{CX_BOTTLE_LOCKED} eq "");
    }
}

sub lock_bottle($)
{
    my ($wineprefix)=@_;
    my $lock;
    my $name=get_bottle_lock_prefix($wineprefix);
    if (($ENV{CX_BOTTLE_LOCKED} || "") !~ /<\Q$name\E>/)
    {
        # We must synchronize with other processes to make sure we don't use a
        # half-created bottle or try to update / upgrade the same bottle twice.
        $lock=CXUtils::cxlock($name);
        if ($lock)
        {
            $lock->{unlock_hook}=\&unlock_bottle;
            $lock->{CX_BOTTLE_LOCKED}=$ENV{CX_BOTTLE_LOCKED};
            $ENV{CX_BOTTLE_LOCKED}=($ENV{CX_BOTTLE_LOCKED} || "") . "<$lock->{name}>";
        }
        else
        {
            cxwarn("$@\n");
            cxwarn("locking failed, continuing without a lock\n");
        }
    }
    return $lock;
}

sub read_bottle_config($$)
{
    my ($cxconfig, $wineprefix)=@_;
    if (!is_initialized())
    {
        my $lock=lock_bottle($wineprefix);
        $cxconfig->read("$wineprefix/cxbottle.conf");
        CXUtils::cxunlock($lock);
    }
    else
    {
        $cxconfig->read("$wineprefix/cxbottle.conf");
    }
}

sub setup_bottle_environment($$)
{
    my ($cxconfig, $wineprefix)=@_;
    read_bottle_config($cxconfig, $wineprefix);
    if (!is_initialized())
    {
        set_environment($cxconfig, "Bottle environment variables");
    }
}

sub get_bottle_mode($$)
{
    my ($cxbottle, $scope)=@_;

    my $updater=$cxbottle->get("Bottle", "Updater");
    if ($scope eq "managed")
    {
        return "managed" if ($updater);
        $@=cxgettext("'Updater' is not set for the '\%s' managed bottle", $ENV{CX_BOTTLE});
        return undef;
    }

    return "private" if (!$updater);
    return "stub";
}

sub bottle_stub2managed($;$)
{
    my ($scope, $raw_wineprefix)=@_;

    if ($scope eq "private")
    {
        require CXConfig;
        my $cxbottle=CXConfig->new();
        read_bottle_config($cxbottle, $ENV{WINEPREFIX});
        my $mode=get_bottle_mode($cxbottle, $scope);
        return (undef, undef) if (!defined $mode);
        return setup_bottle_wineprefix("managed") if ($mode eq "stub");
    }
    return ($scope, $raw_wineprefix);
}

sub get_template_directory($)
{
    my ($cxconfig)=@_;
    my $template=expand_string($cxconfig->get("Bottle", "Template", "win98"));
    my $dir=$template;
    $dir="$ENV{CX_ROOT}/share/crossover/bottle_templates/$dir" if ($dir !~ m%^/$%);
    return (-d $dir ? $dir : undef);
}

sub get_bottle_tag($)
{
    my ($cxconfig)=@_;
    my $productid=CXUtils::get_product_id();
    my $bottleid=$cxconfig->get("Bottle", "BottleID", "");
    return undef if (!$bottleid); # "0" is reserved
    return "$productid-$bottleid";
}

sub get_bottle_status($$$)
{
    my ($cxconfig, $wineprefix, $scope)=@_;

    my ($mode, $status);
    $mode=get_bottle_mode($cxconfig, $scope);
    if (!defined $mode)
    {
        $@="unable to determine the bottle mode\n";
        return (undef);
    }

    if (!is_initialized())
    {
        if ($mode eq "stub")
        {
            my $FILES="files";
            my $managed_wineprefix=CXBottle::find_bottle($ENV{CX_BOTTLE}, "managed");
            my $ref_mtime=(stat("$managed_wineprefix/$FILES"))[9];
            my $bottle_mtime=(stat("$wineprefix/$FILES"))[9] || "";
            $status=(!$bottle_mtime or !$ref_mtime or $bottle_mtime != $ref_mtime) ? "restub" : "uptodate";
        }
        else
        {
            $status="uptodate";
        }
    }
    else
    {
        $status="uptodate";
    }
    return ($mode, $status);
}

sub update_bottle($$$)
{
    if (!is_initialized())
    {
        my ($cxconfig, $wineprefix, $scope)=@_;
        my $mode=get_bottle_mode($cxconfig, $scope);
        return 0 if (!defined $mode);
        my $update;
        if ($mode ne "stub")
        {
            my $crossover_t=$cxconfig->get("CrossOver", "BuildTimestamp", "");
            my $bottle_t=$cxconfig->get("Bottle", "Timestamp", "");
            $update=1 if ($crossover_t ne $bottle_t);
        }
        else
        {
            $update=1;
        }
        if ($update)
        {
            # FIXME: We can't check the return code. Plus if things go wrong
            # it becomes interactive :-(
            cxsystem("$ENV{CX_ROOT}/bin/wine", "--bottle", $ENV{CX_BOTTLE}, "--scope", $scope, "--ux-app", "true");
        }
    }
    return 1;
}

sub run_scripts($$)
{
    my ($dir, $args)=@_;

    my $dh;
    if (!opendir($dh, $dir))
    {
        cxlog("unable to open the '$dir' directory: $!\n");
        return 0;
    }
    my @dentries=readdir $dh;
    closedir($dh);
    foreach my $dentry (sort @dentries)
    {
        next if ($dentry !~ /^[0-9][0-9]\.[^.~]+$/);
        next if (!-x "$dir/$dentry" or !-f _);
        cxsystem("$dir/$dentry", @$args);
    }
}

sub run_bottle_hooks($)
{
    my ($args)=@_;

    my @dirs=("$ENV{CX_ROOT}/support/scripts.d");
    my $user_dir=get_user_dir();
    push @dirs, "$user_dir/scripts.d" if (defined $user_dir);

    # Don't use the scripts in the stub bottles: they will not exist during
    # creation and may be changed during the stub update. Use the managed
    # bottle's scripts instead.
    my $scriptsdir;
    if (-f "$ENV{WINEPREFIX}/cxbottle.conf")
    {
        my $cxconfig=CXBottle::get_crossover_config();
        $cxconfig->read("$ENV{WINEPREFIX}/cxbottle.conf");
        if (!defined $cxconfig->get("Bottle", "Updater"))
        {
            $scriptsdir=$ENV{WINEPREFIX}
        }
    }
    $scriptsdir||=CXBottle::find_bottle($ENV{CX_BOTTLE}, "managed");
    push @dirs, "$scriptsdir/scripts.d";

    foreach my $dir (@dirs)
    {
        run_scripts($dir, $args) if (-d $dir);
    }
}

sub fix_item_ownership_permissions($$$)
{
    my ($path, $egid, $shared)=@_;
    my $dir;

    my ($st_mode, $st_uid, $st_gid)=(lstat($path))[2,4,5];
    $dir=$path if (-d _);
    if (CXLog::is_on())
    {
        cxlog(sprintf("%04o", $st_mode & 07777),
              " - $st_uid - $st_gid - $path\n");
    }
    if ($> == 0 and ($st_uid != 0 or $st_gid != $egid))
    {
        cxlog("  chown 0:$egid $path\n");
        if (-l _)
        {
            # Perl does not have lchown :-(
            cxsystem("chown", "-h", "0:$egid", $path);
        }
        else
        {
            chown 0, $egid, $path;
        }
    }

    # Don't change the permissions on symbolic links
    return $dir if (-l _);

    # Setuid and setgid don't make sense for bottle files and
    # are dangerous. So remove them. Allow the sticky bit though.
    my $mode=($st_mode & (-d _ ? 07777 : 01777)) & ~umask();
    $mode|=($mode & 0100 ? 0055 : 0044) if ($shared);
    if ($mode != ($st_mode & 07777))
    {
        if (CXLog::is_on())
        {
            cxlog("  chmod ", sprintf("%04o", $mode), " $path\n");
        }
        chmod $mode, $path;
    }
    return $dir;
}

sub fix_ownership_permissions($$)
{
    my ($rootdir, $scope)=@_;

    # Fix the user/group ownership, and maybe the permissions too
    my $shared=($scope eq "managed");
    my $egid=$);
    $egid=~s/ .*$//;

    fix_item_ownership_permissions($rootdir, $egid, $shared);

    my @dirs=($rootdir);
    while (@dirs)
    {
        my $dh;
        my $dir=shift @dirs;
        if (!opendir($dh, $dir))
        {
            cxerr("unable to open the '$dir' directory: $!\n");
            next;
        }
        foreach my $dentry (readdir $dh)
        {
            next if ($dentry =~ /^\.\.?$/);
            my $subdir=fix_item_ownership_permissions("$dir/$dentry", $egid, $shared);
            push @dirs, $subdir if (defined $subdir);
        }
        closedir($dh);
    }
}

sub get_desktopdata_dir($$)
{
    my ($scope, $tag)=@_;
    return "$ENV{WINEPREFIX}/desktopdata" if (defined $ENV{WINEPREFIX});
    return undef if (!defined $tag);
    return get_managed_bottle_dir() . "/desktopdata/$tag" if ($scope eq "managed");
    my $user_dir=get_user_dir();
    return "$user_dir/desktopdata/$tag" if (defined $user_dir);
    return undef;
}

sub removeall_desktopdata_dirs($$)
{
    my ($pattern, $subdir)=@_;
    my @dirs=(get_managed_bottle_dir() . "/desktopdata");
    my $user_dir=get_user_dir();
    push @dirs, "$user_dir/desktopdata" if (defined $user_dir);
    foreach my $dir (@dirs)
    {
        next if (!-d $dir or !-w $dir);
        my $dh;
        if (!opendir($dh, $dir))
        {
            cxlog("unable to open the '$dir' directory: $!\n");
            next;
        }
        foreach my $dentry (readdir $dh)
        {
            if ($dentry =~ /^$pattern/)
            {
                my $d="/$dentry/$subdir";
                if (-d "$dir$d")
                {
                    cxlog("Deleting the '$dir$d' directory\n");
                    require File::Path;
                    if (!File::Path::rmtree("$dir$d"))
                    {
                        cxwarn("unable to delete the '$dir$d' directory: $!\n");
                    }
                    CXUtils::garbage_collect_subdirs($dir, cxdirname($d), 1);
                }
            }
        }
        closedir($dh);
        cxlog("Deleted the '$dir' directory\n") if (rmdir $dir);
    }
}

sub count_user_bottles()
{
    my $dir = get_user_bottle_dir();
    my $count = 0;

    my $dh;
    if (!opendir($dh, $dir))
    {
        cxlog("unable to open the '$dir' directory: $!\n");
        return 0;
    }
    my @dentries=readdir $dh;
    closedir($dh);
    foreach my $dentry (@dentries)
    {
        if ((lc($dentry) ne "default") && (-f "$dir/$dentry/system.reg"))
        {
            $count++;
        }
    }
    return $count;
}

return 1;
