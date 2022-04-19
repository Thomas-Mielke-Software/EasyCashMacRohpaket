# (c) Copyright 2006-2012, 2014. CodeWeavers, Inc.
package CXMenuPerm;
use warnings;
use strict;
use CXLog;
use CXUtils;
use CXMenu;
use base "CXMenu";

# Creates "permanent" .desktop files with a stable and predictable filename.

sub detect($$$$)
{
    my ($class, $cxoptions, $cxconfig, $gui_info)=@_;

    if ($gui_info->{macosx_on})
    {
        return ();
    }

    my $self={
        tag             => $cxoptions->{tag},
        desktopdata     => $cxoptions->{desktopdata},
        ro_desktopdata  => $cxoptions->{ro_desktopdata},
        destdir         => $cxoptions->{destdir},
        xdg_dir         => "$cxoptions->{destdir}$gui_info->{xdg_preferred_data}",
    };
    bless $self, $class;
    return ($self);
}

sub id($)
{
    return "CXMenuPerm/";
}


sub install($$)
{
    my ($self, $components)=@_;

    my $menu=@$components[-1];

    return 1 if ($menu->{is_dir} or not defined $self->{desktopdata});

    # Remove the parent directory from the garbage collection list
    my $path=$menu->{rawpath};
    delete $self->{garbage_collect}->{cxdirname($path)};

    # Install the icon
    $menu->{_creator}="";
    CXMenu::xdg_install_icons($self->{xdg_dir}, $self->{tag}, $menu);

    my $launcher="$self->{desktopdata}/cxmenu/Launchers/$path.desktop";
    cxlog("Creating '$launcher'\n");

    my $dir=cxdirname($launcher);
    if (!cxmkpath($dir))
    {
        cxerr("unable to create '$dir': $@\n");
        return -1; # Fatal error
    }

    if ($self->{ro_desktopdata} and -f $launcher)
    {
        # Assume this is our launcher
    }
    else
    {
        $menu->{_categories}=undef;
        $menu->{_creator}=" (" . $self->id() . ")" if ($ENV{CX_TAGALL});
        if (!CXMenu::xdg_create_desktop_file($launcher, $menu))
        {
            return 0;
        }
    }

    return 1;
}

sub query($$)
{
    my ($self, $components)=@_;
    return ("", $self->id()) if (!defined $components);

    my $menu=@$components[-1];
    return "" if ($menu->{is_dir} or not defined $self->{desktopdata});

    my $path="$self->{desktopdata}/cxmenu/Launchers/$menu->{rawpath}.desktop";

    cxlog("checking for '$path'\n");
    if (-f $path)
    {
        require CXRWConfig;
        my $file=CXRWConfig->new($path, "xdg", "");
        foreach my $name ($file->get_section_names())
        {
            my $created_by=$file->get($name, "X-Created-By");
            if (defined $created_by)
            {
                if (grep /^$self->{tag}$/, split /;+/, $created_by)
                {
                    return $self->id();
                }
                last;
            }
        }
    }
    return "";
}

sub get_files($$)
{
    my ($self, $components)=@_;

    my $menu=@$components[-1];
    return [] if ($menu->{is_dir} or not defined $self->{desktopdata});

    my @files;
    push @files, @{CXMenu::xdg_get_icon_files($self->{destdir}, $self->{xdg_dirs}, $self->{tag}, $menu)};
    my $path="$self->{desktopdata}/cxmenu/Launchers/$menu->{rawpath}.desktop";
    if (-f $path)
    {
        require CXRWConfig;
        my $file=CXRWConfig->new($path, "xdg", "");
        foreach my $name ($file->get_section_names())
        {
            my $created_by=$file->get($name, "X-Created-By");
            if (defined $created_by)
            {
                push @files, $path if (grep /^$self->{tag}$/, split /;+/, $created_by);
                last;
            }
        }
    }
    return \@files;
}

sub uninstall($$)
{
    my ($self, $components)=@_;

    my $menu=@$components[-1];
    return 1 if ($menu->{is_dir} or not defined $self->{desktopdata});

    my $launcher="$self->{desktopdata}/cxmenu/Launchers/$menu->{rawpath}.desktop";

    if (!$self->{ro_desktopdata} and -f $launcher)
    {
        cxlog("Deleting '$launcher'\n");
        if (!unlink $launcher)
        {
            cxwarn("unable to delete '$launcher': $!\n");
        }
    }

    # Also mark the parent directory for deletion
    $self->{garbage_collect}->{cxdirname($launcher)}=1;

    return 1;
}

sub removeall($$)
{
    my ($self, $pattern)=@_;

    if (!$self->{ro_desktopdata} and defined $self->{desktopdata} and
        $pattern ne "legacy" and ($self->{tag} || "") =~ /^$pattern/)
    {
        my $dir="$self->{desktopdata}/cxmenu/Launchers";
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
    return 1;
}

sub finalize($)
{
    my ($self)=@_;
    return 1 if ($self->{ro_desktopdata} or not defined $self->{desktopdata});

    my $root="$self->{desktopdata}/cxmenu";
    foreach my $path (sort { $b cmp $a } keys %{$self->{garbage_collect}})
    {
        CXUtils::garbage_collect_subdirs($root, $path, 1);
    }
    CXUtils::garbage_collect_subdirs($self->{desktopdata}, "/cxmenu", 1);
    return 1;
}

return 1;
