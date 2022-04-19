# (c) Copyright 2005-2014. CodeWeavers, Inc.
package CXMenuWindows;
use warnings;
use strict;

use CXLog;
use CXUtils;
use CXMenu;

sub remove_spaces($)
{
    my ($str)=@_;
    # We really only want to remove spaces because they trigger GNOME
    # bug 700320.
    # But to avoid collisions (for instance between 'a b' and 'a+b') we have
    # to go a bit further. But we still don't want to use full on mangling
    # (aka CXUtils.mangle_string()) because it seems unnecessary and tends to
    # generate overly long filenames with double-byte languages.
    $str =~ s!([+^])!sprintf "^%02X", ord($1)!eg;
    $str =~ s! !+!g;
    return $str;
}

sub detect($$$$)
{
    my ($class, $cxoptions)=@_;

    my $self={
        tag             => $cxoptions->{tag},
        desktopdata     => $cxoptions->{desktopdata},
        ro_desktopdata  => $cxoptions->{ro_desktopdata},
    };
    bless $self, $class;
    return ($self);
}

sub id($)
{
    return "CXMenuWindows/";
}

my $wine_script;
sub get_wine_script()
{
    $wine_script=shquote_string("$ENV{CX_ROOT}/bin/wine") if (!defined $wine_script);
    return $wine_script;
}

sub get_command($;$)
{
    my ($menu, $background)=@_;

    my $lnk=CXMenu::menu_to_lnk($menu->{rawpath});

    # 'wine --start' really expects the parameter to be in the default encoding
    require CXRecode;
    $lnk=CXRecode::to_sys("UTF-8", $lnk);

    return join(" ", get_wine_script(),
                "--bottle", shquote_string($ENV{CX_BOTTLE}),
                "--check", ($background ? "--no-wait" : "--wait-children"),
                "--start", shquote_string($lnk));
}

sub delete($)
{
    my ($rawpath)=@_;

    my $wlnk=CXMenu::menu_to_lnk($rawpath);
    # 'winepath' really expects the parameter to be in the default encoding
    require CXRecode;
    $wlnk=CXRecode::to_sys("UTF-8", $wlnk);

    my $ulnk=cxbackquote(get_wine_script() . " --no-convert --wl-app winepath.exe " . shquote_string($wlnk));
    return 0 if ($? ne 0);
    chomp $ulnk;
    return 0 if (!unlink $ulnk);
    return 1;
}

sub install($$)
{
    my ($self, $components)=@_;

    my $menu=@$components[-1];
    return 1 if ($menu->{type} ne "windows");

    if (!defined $ENV{WINEPREFIX})
    {
        cxerr("cannot create the '$menu->{rawpath}' Windows menu because no bottle was specified\n");
        return -1; # Fatal error
    }
    if ($menu->{command} ne "")
    {
        cxwarn("'windows' menus cannot have a command. Overriding the command\n");
    }

    # The icon, if any, will be relative to the bottle
    $menu->{icon_root}||="$ENV{WINEPREFIX}/windata/cxmenu/icons";
    return 1 if ($menu->{is_dir});

    # Remove the parent directory from the garbage collection list
    my $path=remove_spaces($menu->{rawpath});
    delete $self->{garbage_collect}->{cxdirname($path)};

    my $script="$self->{desktopdata}/cxmenu/$path";
    cxlog("Creating '$script'\n");

    my $scriptdir=cxdirname($script);
    if (!cxmkpath($scriptdir))
    {
        cxerr("unable to create '$scriptdir': $@\n");
        return -1; # Fatal error
    }

    if ($self->{ro_desktopdata} and -f $script and -x _)
    {
        # Assume this is our script
    }
    elsif (open(my $fh, ">", $script))
    {
        print $fh "#!/bin/sh\n";
        print $fh "exec ", get_command($menu),  " \"\$\@\"\n";
        close($fh);
        chmod(0777 & ~umask(), $script);
    }
    else
    {
        cxerr("unable to open '$script' for writing: $!\n");
        return -1; # Fatal error
    }

    $menu->{command}=shquote_string($script);
    $menu->{genericname}="Windows Application (CrossOver)";
    return 1;
}

sub query($$)
{
    # Don't report the CXMenuWindows install status
    return ("", "");
}

sub get_files($$)
{
    my ($self, $components)=@_;

    my $menu=@$components[-1];
    return [] if ($menu->{type} ne "windows" or $menu->{is_dir});

    # The icon, if any, will be relative to the bottle
    if (defined $ENV{WINEPREFIX})
    {
        $menu->{icon_root}||="$ENV{WINEPREFIX}/windata/cxmenu/icons";
    }

    # The script is inside the CrossOver bottle
    # but would not normally get packaged.
    my $script="$self->{desktopdata}/cxmenu/". remove_spaces($menu->{rawpath});
    return -f $script ? [$script] : [];
}

sub uninstall($$)
{
    my ($self, $components)=@_;

    my $menu=@$components[-1];
    return 1 if ($menu->{is_dir});
    return 1 if ($menu->{type} ne "windows" and !defined $ENV{WINEPREFIX});
    # Do the uninstall for non-Windows menus so we clean up after them
    # in case their type changed

    if (!defined $ENV{WINEPREFIX})
    {
        cxerr("cannot remove the script associated to the '$menu->{rawpath}' Windows menu because no bottle was specified\n");
        return 0;
    }

    my $path=remove_spaces($menu->{rawpath});
    my $script="$self->{desktopdata}/cxmenu/$path";
    if (!$self->{ro_desktopdata} and -f $script)
    {
        cxlog("Deleting '$script'\n");
        if (!unlink $script)
        {
            cxwarn("unable to delete '$script': $!\n");
        }
    }

    # Also mark the parent directory for deletion
    $self->{garbage_collect}->{cxdirname($path)}=1;

    return 1;
}

sub removeall($$)
{
    my ($self, $pattern)=@_;

    if (!$self->{ro_desktopdata} and defined $ENV{WINEPREFIX} and
        $pattern ne "legacy" and ($self->{tag} || "") =~ /^$pattern/)
    {
        if (opendir(my $dh, "$self->{desktopdata}/cxmenu"))
        {
            foreach my $dentry (readdir $dh)
            {
                next if ($dentry !~ /^(?:Desktop|StartMenu)/);
                my $dir="$self->{desktopdata}/cxmenu/$dentry";
                next if (!-d $dir);

                cxlog("Deleting the '$dir' directory\n");
                require File::Path;
                if (!File::Path::rmtree($dir))
                {
                    cxerr("unable to delete the '$dir' directory: $!\n");
                }
            }
            closedir($dh);
        }
        CXUtils::garbage_collect_subdirs($self->{desktopdata}, "/cxmenu", 1);
    }
    return 1;
}

sub finalize($)
{
    my ($self)=@_;
    return 1 if ($self->{ro_desktopdata} or !defined $ENV{WINEPREFIX});

    my $root="$self->{desktopdata}/cxmenu";
    foreach my $path (sort { $b cmp $a } keys %{$self->{garbage_collect}})
    {
        CXUtils::garbage_collect_subdirs($root, $path, 1);
    }
    CXUtils::garbage_collect_subdirs($self->{desktopdata}, "/cxmenu", 1);
    return 1;
}

return 1;
