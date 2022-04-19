# (c) Copyright 2006, 2008, 2010, 2014. CodeWeavers, Inc.
package CXMenuCDE;
use warnings;
use strict;
use CXLog;
use CXUtils;
use CXMenu;
use base "CXMenu";
use CXCDE;


sub read_dt_file($)
{
    my ($self)=@_;
    if (!$self->{dtfile})
    {
        $self->{dtfile}=CXCDE->new("$self->{dtdir}/cxmenu-$self->{tag}.dt");
    }
    return ($self->{dtfile} ? 1 : 0);
}

sub detect($$$$)
{
    my ($class, $cxoptions, $cxconfig, $gui_info)=@_;
    return () if (!$gui_info->{cde_on});

    my $self={
        tag         => $cxoptions->{tag},
        destdir     => $cxoptions->{destdir},
        scope       => $gui_info->{preferred_scope},
        wmdir       => "$cxoptions->{destdir}$gui_info->{cde_preferred_wm}",
        dtdir       => "$cxoptions->{destdir}$gui_info->{cde_preferred_dt}",
    };

    if ($self->{scope} ne "managed")
    {
        $self->{dtaction}=CXUtils::cxwhich("$ENV{PATH}:/usr/dt/bin", "dtaction");
        if (!defined $self->{dtaction})
        {
            cxlog("unable to find 'dtaction'. Maybe you need to install the SUNWdtbas package?\n");
            return ();
        }
    }

    bless $self, $class;
    return ($self);
}

sub id($)
{
    my ($self)=@_;
    my $id="CXMenuCDE/$self->{wmdir}";
    $id =~ s%/+%/%g;
    return $id;
}

sub install($$)
{
    my ($self, $components)=@_;

    my $menu=$components->[-1];
    # We don't support desktop icons
    return 1 if ($menu->{is_desktop});
    return 0 if (!$self->read_dt_file());

    if ($self->{scope} ne "managed" and $self->{destdir} eq "" and
        !-d $self->{wmdir})
    {
        # Create ~/.dt/wsmenu and populate it with the global menus
        # Also updates ~/.dt/$LANG/wsmenu.dtwmrc but we don't care yet
        # Make sure we only run one instance at a time (just to be safe).
        my $lock=CXUtils::cxlock("cde");
        if (!-d $self->{wmdir} and
            cxsystem($self->{dtaction}, "BuildDtwmrcFromWsmenuDir"))
        {
            cxlog("unable to create '$self->{wmdir}'\n");
            CXUtils::cxunlock($lock);
            return 0;
        }
        CXUtils::cxunlock($lock);
    }

    my $dir=$self->{wmdir} . ($menu->{is_dir} ? $menu->{path} : $menu->{dir});
    if (!-d $dir)
    {
        foreach my $component (@$components)
        {
            last if (!$component->{is_dir});
            my $dir="$self->{wmdir}/$component->{path}";
            if (!cxmkpath($dir))
            {
                cxerr("unable to create the '$dir' directory: $@\n");
                return 0;
            }
        }
    }

    if ($menu->{is_dir})
    {
        # Make sure our brand new (maybe empty) folder will not be
        # 'garbage collected' by finalize()
        $self->{status}->{$menu->{path}}="in-use";
    }
    else
    {
        $self->{status}->{$menu->{dir}}="in-use";

        # Create a new action
        my $icon=CXMenu::get_unix_icon_path($menu) ||
                 CXMenu::get_default_icon_path(0);
        my $action={LABEL       => $menu->{name},
                    TYPE        => "COMMAND",
                    EXEC_STRING => $menu->{command},
                    ICON        => $icon,
                    WINDOW_TYPE => "NO_STDIO"
                   };
        my $mangled="cxmenu-$self->{tag}" . mangle_string($menu->{path});
        $self->{dtfile}->{actions}->{$mangled}=$action;
        $self->{modified}=1;

        # Reference that action in the Workspace Menu
        my $fh;
        if (!open($fh, ">", "$dir/$mangled"))
        {
            cxerr("unable to open '$dir/$mangled' for writing: $!\n");
            return 0;
        }
        print $fh "#!/bin/sh\n";
        print $fh "# X-Created-By=$mangled\n";
        print $fh "exec dtaction \"$mangled\" \"\$\@\"\n";
        close($fh);
        chmod(0777 & ~umask(), "$dir/$mangled");
    }

    return 1;
}

sub query($$)
{
    my ($self, $components)=@_;
    return ($self->id(), "") if (!defined $components);

    my $menu=$components->[-1];
    # We don't support desktop icons
    return "" if ($menu->{is_desktop});
    return 0 if (!$self->read_dt_file());

    if (!$menu->{is_dir})
    {
        my $mangled="cxmenu-$self->{tag}" . mangle_string($menu->{path});
        return "" if (!$self->{dtfile}->{actions}->{$mangled});
        my $filename="$self->{wmdir}$menu->{dir}/$mangled";
        return "" if (!-x $filename);
    }
    else
    {
        return "" if (!-d "$self->{wmdir}$menu->{path}");
    }
    return $self->id();
}

sub get_files($$)
{
    my ($self, $components)=@_;

    my $menu=$components->[-1];
    # We don't support desktop icons
    return [] if ($menu->{is_desktop} or !$self->read_dt_file());

    if (!$menu->{is_dir})
    {
        my $filename=$self->{wmdir} . $menu->{dir} . "cxmenu-$self->{tag}" . mangle_string($menu->{path});
        return [$filename] if (-f $filename);
    }
    return [];
}

sub uninstall($$)
{
    my ($self, $components)=@_;

    my $menu=$components->[-1];
    # We don't support desktop icons
    return 1 if ($menu->{is_desktop});
    return 0 if (!$self->read_dt_file());

    # Always mark the parent folder for garbage collection
    $self->{garbage_collect}->{$menu->{dir}}=1;

    # FIXME: We should also handle the is_dir case
    if (!$menu->{is_dir})
    {
        my $mangled="cxmenu-$self->{tag}" . mangle_string($menu->{path});
        delete $self->{dtfile}->{actions}->{$mangled};
        $self->{modified}=1;

        my $filename="$self->{wmdir}$menu->{dir}/$mangled";
        if (-f $filename)
        {
            cxlog("Deleting '$filename'\n");
            if (!unlink $filename)
            {
                cxerr("unable to delete '$filename': $1\n");
                return 0;
            }
        }
    }

    return 1;
}

# This function assumes that it is being called before any of the others
# which means it does not have to clean up 'filename', 'actions', etc.
sub removeall($$)
{
    my ($self, $pattern)=@_;

    my $dt_pattern;
    if ($pattern eq "legacy")
    {
        $dt_pattern="^" . CXUtils::get_product_id() . "\\..*\\.(?:dt|fp)\$";
    }
    else
    {
        $pattern.=".*" if ($pattern !~ s/\$$//);
        $dt_pattern="^cxmenu-$pattern\\.dt\$";
    }
    cxlog("dt_pattern=[$dt_pattern]\n");

    # Delete the dt file
    if (CXUtils::delete_files($self->{dtdir}, $dt_pattern) > 0)
    {
        $self->{update}=1;
    }

    # And the Workspace Menu files that refer to them
    $pattern="^cxmenu-${pattern}_";
    $dt_pattern.=".*" if ($dt_pattern !~ s/\$$//);
    cxlog("pattern=[$pattern]\n");
    my $rc=1;
    my @dirs=("");
    while (@dirs)
    {
        my $dir=shift @dirs;
        if (opendir(my $dh, "$self->{wmdir}$dir"))
        {
            cxlog("$dir\n");
            foreach my $dentry (readdir $dh)
            {
                next if ($dentry =~ m/^\.\.?$/);
                cxlog("  [$dentry]\n");
                if ($dentry =~ /$pattern/)
                {
                    $dentry="$self->{wmdir}$dir/$dentry";
                    cxlog("Deleting '$dentry'\n");
                    if (!unlink $dentry)
                    {
                        cxerr("unable to delete '$dentry': $!\n");
                        $rc=0;
                    }
                    $self->{update}=1;
                }
                elsif (-d "$self->{wmdir}$dir/$dentry")
                {
                    push @dirs, "$dir/$dentry";
                    $self->{garbage_collect}->{"$dir/$dentry"}=1;
                }
            }
            closedir($dh);
        }
        elsif (-d "$self->{wmdir}$dir")
        {
            cxlog("unable to open the '$self->{wmdir}$dir' directory: $!\n");
            $rc=0;
        }
    }

    return $rc;
}

sub gc_get_folder_status($$)
{
    my ($self, $path)=@_;

    my @actions=keys %{$self->{dtfile}->{actions}};
    if (@actions)
    {
        # If actions is non-empty, then install() was called,
        # and thus tag is set
        cxlog("actions=[", join(":", @actions),"]\n");
        my $mangled="cxmenu-$self->{tag}" . mangle_string("$path/");
        return "in-use" if (grep m%^\Q$mangled\E$%, @actions);
    }

    if (opendir(my $dh, "$self->{wmdir}$path"))
    {
        foreach my $dentry (readdir $dh)
        {
            if ($dentry !~ /^\.\.?$/)
            {
                closedir($dh);
                return "in-use";
            }
        }
        closedir($dh);
    }
    return "empty";
}

sub gc_delete_folder($$$)
{
    my ($self, $path)=@_;

    cxlog("Deleting the '$path' directory\n");
    my $dir="$self->{wmdir}$path";
    if (-d $dir)
    {
        cxlog("Deleting '$dir'\n");
        if (!rmdir $dir)
        {
            cxerr("unable to delete the '$dir' directory: $!\n");
            return 0;
        }
    }
}

sub finalize($)
{
    my ($self)=@_;

    $self->SUPER::finalize();

    if ($self->{modified})
    {
        if ($self->{dtfile}->is_empty())
        {
            my $filename="$self->{destdir}$self->{dtfile}->{filename}";
            cxlog("deleting empty '$filename' file\n");
            # Delete the menu file
            if (-e $filename and !unlink $filename)
            {
                cxerr("unable to delete '$filename': $!\n");
                return 0;
            }
        }
        elsif (!$self->{dtfile}->save())
        {
            cxerr("unable to save '$self->{dtfile}->{filename}'\n");
        }
        $self->{update}=1;
    }
    if ($self->{update} and $self->{scope} ne "managed")
    {
        # Make sure we only run one instance at a time (just to be safe).
        my $lock=CXUtils::cxlock("cde");
        # Update ~/.dt/$LANG/wsmenu.dtwmrc
        cxsystem($self->{dtaction}, "BuildDtwmrcFromWsmenuDir");
        # And cause CDE to reload it
        cxsystem($self->{dtaction}, "RegenerateWorkspaceMenu");
        CXUtils::cxunlock($lock);
    }
    return 1;
}

return 1;
