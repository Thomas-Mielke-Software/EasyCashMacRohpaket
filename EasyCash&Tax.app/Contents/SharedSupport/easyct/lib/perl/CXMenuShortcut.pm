# (c) Copyright 2005-2010, 2014. CodeWeavers, Inc.
package CXMenuShortcut;
use warnings;
use strict;
use CXLog;
use CXUtils;
use CXMenu;

sub detect($$$$)
{
    my ($class, $cxoptions, $cxconfig, $gui_info)=@_;

    my $prefix=($gui_info->{preferred_scope} eq "managed" ? "Managed" : "Private");
    my $shortcutdirs=expand_string($cxconfig->get("CrossOver", "${prefix}ShortcutDirs", ""));

    my $self={
        tag             => $cxoptions->{tag},
        destdir         => $cxoptions->{destdir},
        desktopdata     => $cxoptions->{desktopdata},
        ro_desktopdata  => $cxoptions->{ro_desktopdata},
        shortcutdirs    => $shortcutdirs,
    };
    bless $self, $class;
    return ($self);
}

sub id($)
{
    return "CXMenuShortcut/";
}

sub get_directories($;$)
{
    my ($self, $readonly)=@_;

    my $directories=$self->{directories};
    if (!defined $directories)
    {
        $directories=[];
        foreach my $dir (split /:+/, $self->{shortcutdirs})
        {
            next if ($dir eq "");
            # Skip missing directories without complaining
            next if (!-e $dir);
            if (!-d _)
            {
                cxwarn("'$dir' is not a valid shortcut directory\n");
            }
            elsif (!$readonly and !-w _)
            {
                cxwarn("'$dir' is not writable\n");
            }
            else
            {
                push @$directories, $dir;
            }
        }
        $self->{directories}=$directories;
    }
    return $directories;
}

sub is_shortcut_script($)
{
    my ($path)=@_;
    # Return undef if $path does not exist, 1 if it is a shortcut script,
    # and 0 otherwise (i.e. exists but is not a shortcut script).

    if (-l $path)
    {
        my $dst=readlink $path;
        return 1 if ($dst =~ m%/cxmenu/Shortcuts/%);
        return 0;
    }
    return undef if (!-e _);
    return 0;
}

sub is_dir_in_path($$)
{
    my ($self, $dir)=@_;
    return undef if (!-d $dir);
    my ($dev, $ino)=(stat(_))[0, 1];

    if (!$self->{path_dirs})
    {
        $self->{path_dirs}={};
        foreach my $d (split /:/, $ENV{PATH})
        {
            next if (!-d $d);
            my ($dev, $ino)=(stat(_))[0, 1];
            $self->{path_dirs}->{"$dev:$ino"}=1;
        }
    }
    return $self->{path_dirs}->{"$dev:$ino"};
}

sub install($$)
{
    my ($self, $components)=@_;

    my $menu=@$components[-1];
    return 1 if ($menu->{shortcut} eq "");
    cxlog("Installing shortcut '$menu->{shortcut}'\n");

    if ($menu->{is_dir})
    {
        cxerr("'$menu->{rawpath}': directories cannot have shortcuts. Ignoring it\n");
        return 0;
    }

    my $root="$self->{desktopdata}/cxmenu/Shortcuts";
    if (!cxmkpath($root))
    {
        cxerr("unable to create '$root': $@\n");
        return -1; # Fatal error
    }

    my $script="$root/$menu->{tag}." . mangle_string($menu->{shortcut});
    cxlog("Creating '$script'\n");
    if ($self->{ro_desktopdata} and -f $script and -x _)
    {
        # Assume this is our script
    }
    elsif (open(my $fh, ">", $script))
    {
        print $fh "#!/bin/sh\n";
        print $fh "exec $menu->{command} \"\$\@\"\n";
        close($fh);
        chmod(0777 & ~umask(), $script);
    }
    else
    {
        cxerr("unable to open '$script' for writing: $!\n");
        return -1; # Fatal error
    }

    my $in_path=CXUtils::cxwhich($ENV{PATH}, $menu->{shortcut});
    $in_path=undef if ($in_path and is_shortcut_script($in_path));

    foreach my $dir (@{$self->get_directories()})
    {
        if ($in_path and $self->is_dir_in_path($dir))
        {
            cxlog("skipping $dir because it is in \$PATH\n");
            next;
        }
        my $shortcut="$self->{destdir}$dir/$menu->{shortcut}";

        # First delete the existing shortcut if any,
        # even if it belongs to another CrossOver product.
        my $is_shortcut=is_shortcut_script($shortcut);
        if ($is_shortcut)
        {
            cxlog("Deleting '$shortcut'\n");
            unlink $shortcut;
            $is_shortcut=undef;
        }
        if (!defined $is_shortcut)
        {
            cxlog("Symlinking '$shortcut'\n");
            if (!symlink $script, $shortcut)
            {
                cxlog("unable to symlink '$shortcut' to '$script'\n");
            }
        }
    }
    return 1;
}

sub query($$)
{
    # Don't report the CXMenuShortcut install status
    return ("", "");
}

sub get_files($$)
{
    my ($self, $components)=@_;

    my $menu=@$components[-1];
    return [] if ($menu->{is_dir} or $menu->{shortcut} eq "");

    my @files;
    # This script is inside the CrossOver bottle
    # but would not normally get packaged.
    my $script="$self->{desktopdata}/cxmenu/Shortcuts/$menu->{tag}." . mangle_string($menu->{shortcut});
    push @files, $script if (-f $script);

    foreach my $dir (@{$self->get_directories(1)})
    {
        my $shortcut="$self->{destdir}$dir/$menu->{shortcut}";
        if (-l $shortcut)
        {
            my $dst=readlink $shortcut;
            push @files, $shortcut if ($dst =~ m%/cxmenu/Shortcuts/$menu->{tag}\.%);
        }
    }

    return \@files;
}

sub uninstall($$)
{
    my ($self, $components)=@_;

    my $menu=@$components[-1];
    return 1 if (!defined $menu->{shortcut} or $menu->{shortcut} eq "");

    my $script="$self->{desktopdata}/cxmenu/Shortcuts/$menu->{tag}." .
               mangle_string($menu->{shortcut});
    if (!$self->{ro_desktopdata} and -f $script)
    {
        cxlog("Deleting '$script'\n");
        if (!unlink $script)
        {
            cxerr("unable to delete '$script': $!\n");
        }
    }

    foreach my $dir (@{$self->get_directories()})
    {
        my $shortcut="$self->{destdir}$dir/$menu->{shortcut}";
        if (-l $shortcut)
        {
            my $dst=readlink $shortcut;
            if ($dst =~ m%/cxmenu/Shortcuts/$menu->{tag}\.%)
            {
                cxlog("Deleting '$shortcut'\n");
                if (!unlink $shortcut)
                {
                    cxerr("unable to delete '$shortcut': $!\n");
                }
            }
            else
            {
                cxlog("'$shortcut' is not a CrossOver shortcut\n");
            }
        }
    }

    return 1;
}

sub is_legacy_file($)
{
    my ($filename)=@_;

    my $fh;
    return 0 if (!open($fh, "<", $filename));
    while (my $line=<$fh>)
    {
        if ($line =~ /^#cxmenu auto generated/)
        {
            close($fh);
            return 1;
        }
    }
    close($fh);
    return 0;
}

sub removeall($$)
{
    my ($self, $pattern)=@_;

    if ($pattern eq "legacy")
    {
        # The legacy shortcuts were very different :-(
        if (-w "/usr/bin" and opendir(my $dh, "/usr/bin"))
        {
            foreach my $dentry (readdir $dh)
            {
                next if ($dentry =~ /^\.\.?$/);
                $dentry="/usr/bin/$dentry";

                # Note: -l does an lstat() but we want a stat() for -f
                #       and -e so we must be careful when using _
                next if (!-l $dentry or (!-f $dentry and -e _));
                my $dst=readlink $dentry;
                if ($dst =~ m%$ENV{CX_ROOT}/bin/% and is_legacy_file($dentry))
                {
                    cxlog("Deleting '$dentry'\n");
                    if (!unlink $dentry)
                    {
                        cxerr("unable to delete '$dentry': $!\n");
                    }
                }
            }
            closedir($dh);
        }
        if (-w "$ENV{CX_ROOT}/bin" and opendir(my $dh, "$ENV{CX_ROOT}/bin"))
        {
            foreach my $dentry (readdir $dh)
            {
                next if ($dentry =~ /^\.\.?$/);
                $dentry="$ENV{CX_ROOT}/bin/$dentry";

                if (is_legacy_file($dentry))
                {
                    cxlog("Deleting '$dentry'\n");
                    if (!unlink $dentry)
                    {
                        cxerr("unable to delete '$dentry': $!\n");
                    }
                }
            }
            closedir($dh);
        }
        return 1;
    }

    if (!$self->{ro_desktopdata})
    {
        if ($self->{tag} and $self->{tag} =~ /^$pattern/)
        {
            my $dir="$self->{desktopdata}/cxmenu/Shortcuts";
            if (-d $dir)
            {
                cxlog("Deleting the '$dir' directory\n");
                require File::Path;
                if (!File::Path::rmtree($dir))
                {
                    cxerr("unable to delete the '$dir' directory: $!\n");
                }
            }
            CXUtils::garbage_collect_subdirs($self->{desktopdata}, "/cxmenu", 1);
        }
        else
        {
            require CXBottle;
            CXBottle::removeall_desktopdata_dirs($pattern, "/cxmenu/Shortcuts");
        }
    }

    $pattern =~ s/\$$/\\./;
    foreach my $dir (@{$self->get_directories()})
    {
        my $dh;
        next if (!opendir($dh, $dir));
        foreach my $dentry (readdir $dh)
        {
            next if ($dentry =~ /^\.\.?$/);
            $dentry="$dir/$dentry";

            next if (!-l $dentry);
            my $dst=readlink $dentry;
            if ($dst =~ m%/cxmenu/Shortcuts/$pattern%)
            {
                cxlog("Deleting '$dentry'\n");
                if (!unlink $dentry)
                {
                    cxerr("unable to delete '$dentry'\n");
                }
            }
            else
            {
                cxlog("'$dentry' is not a CrossOver shortcut\n");
            }
        }
        closedir($dh);
    }

    return 1;
}

sub finalize($)
{
    my ($self)=@_;
    if (!$self->{ro_desktopdata} and defined $self->{desktopdata})
    {
        CXUtils::garbage_collect_subdirs($self->{desktopdata}, "/cxmenu/Shortcuts", 1);
    }
    return 1;
}

return 1;
