# (c) Copyright 2005-2008, 2010, 2014. CodeWeavers, Inc.
package CXMenuDebian;
use warnings;
use strict;
use CXLog;
use CXUtils;
use CXMenu;
use base "CXMenu";

sub detect($$$$)
{
    my ($class, $cxoptions, $cxconfig, $gui_info)=@_;
    return () if (!$gui_info->{debian_menu_on});

    my @selves;
    if ($gui_info->{debian_preferred_menu})
    {
        my $self={
            tag             => $cxoptions->{tag},
            destdir         => $cxoptions->{destdir},
            menu            => "$cxoptions->{destdir}$gui_info->{debian_preferred_menu}",
            old_menu        => "$cxoptions->{destdir}$gui_info->{debian_old_preferred_menu}",
        };
        bless $self, $class;
        push @selves, $self;
    }

    return @selves;
}

sub id($)
{
    my ($self)=@_;
    my $id="CXMenuDebian/$self->{menu}";
    $id =~ s%/+%/%g;
    return $id;
}

sub read_menu_file($)
{
    my ($self)=@_;

    return 1 if (defined $self->{filename});
    $self->{filename}="$self->{menu}/cxmenu-$self->{tag}";
    if ($self->{old_menu})
    {
        my $old_filename="$self->{old_menu}/cxmenu-$self->{tag}";
        if (-f $old_filename and !-f $self->{filename})
        {
            if (!cxmv($old_filename, $self->{filename}))
            {
                cxwarn("unable to rename '$old_filename' to '$self->{filename}': $!\n");
            }
            # Delete the parent directory if it's empty
            rmdir $self->{old_menu};
        }
    }
    $self->{lines}=[];
    $self->{menus}={};
    $self->{modified}=0;
    return 1 if (!-e $self->{filename});

    cxlog("Reading '$self->{filename}'\n");
    my $fh;
    if (!open($fh, "<", $self->{filename}))
    {
        cxerr("unable to open '$self->{filename}' for reading: $!\n");
        return 0;
    }

    my $count=0;
    foreach my $line (<$fh>)
    {
        chomp $line;
        push @{$self->{lines}}, $line;
        #cxlog(" line=[$line]\n");
        if ($line =~ /(?:\s|:)section=\"(\/(?:[^\\\"]*|\\.)*)\"\s+title=\"((?:[^\\\"]*|\\.)*)\"(?:\s|$)/)
        {
            my $dir=$1;
            my $name=$2;
            #cxlog("  1=[$dir] 2=[$name]\n");
            my $path=unescape_string($dir);
            $path.="/" if ($path !~ m%/$%);
            $path.=unescape_string($name);
            if ($line !~ /(?:\s|:)command=\"((?:[^\\\"]*|\\.)*)\"(?:\s|$)/)
            {
                # This would be a menu folder
                $path.="/";
            }
            $self->{menus}->{$path}=$count;
        }
        $count++;
    }
    close($fh);
    # For debug...
    # map { cxlog("  $_\n"); } keys %{$self->{menus}};

    return 1;
}

sub create_component($$$)
{
    my ($self, $dir, $component)=@_;

    if (!exists $self->{hacks})
    {
        $self->{hacks}={};
        if (CXUtils::file_grep("/etc/mandriva-release", "release\\s+2006\\.0[^0-9]"))
        {
            # Notes:
            # - Mandriva 2006.0 passes the '<', '>' and '&' characters
            #   straight to XDG's XML file which causes a parse error, and
            #   the user to lose all his menus.
            # - It also puts ';' straight into the folder's keyword which
            #   causes the loss of that folder as ';' is also the keyword
            #   separator in .desktop files.
            cxlog("Detected Mandriva 2006.0\n");
            $self->{hacks}->{badxdg}=1;
        }
    }

    my $path="$dir$component->{name}";
    $path.="/" if ($component->{is_dir});

    my $line=$self->{menus}->{$path};
    if (!defined $line or !$component->{intermediate})
    {
        cxlog("  creating path='$path'\n");
        my $name=$component->{name};
        if ($ENV{CX_TAGALL} and !$component->{is_dir})
        {
            my $creator=$self->id();
            $creator =~ s%/%-%g;
            $name.=" ($creator)";
        }

        # Notes:
        # - The specification says to use ASCII 7bit but in practice using
        #   UTF-8 work fine and lets accents go through. Furthermore, recent
        #   versions (at least on Mandrake >= 10.1) have a charset property.
        # - Double quotes and backslashes are allowed by the specification
        #   but some update-menus plugins (e.g. Enlightenment on Mandrake 8.2)
        #   are buggy and can be confused by double-quotes in the section
        #   field etc. Since this is plugin and distribution specific we
        #   ignore such issues.
        # - Backslashes must be quadrupled on all platforms. The current
        #   theory is that this is because escape sequences like '\t' are
        #   interpreted which we do not want.
        # - On a related note, complex escape sequences like \\\" are causing
        #   a global meltdown in  Mandrake 8.2 to 9.2. Quadrupling backslashes
        #   avoids this problem.
        # - No need to escape '$'s though some of the update-menus
        #   plugins (e.g. KDE) handle them incorrectly.
        $dir=~s%/$%% if ($dir ne "/");
        if ($self->{hacks}->{badxdg})
        {
            $dir =~ s/[<>&;]//g;
            $name =~ s/[<>&;]//g if ($component->{is_dir});
        }
        my $str="?package(local." . CXUtils::get_product_id() .
                "): charset=\"utf8\" needs=\"x11\" section=\"" .
                escape_string($dir) . "\" title=\"" . escape_string($name) .
                "\"";
        if (($component->{description} || "") ne "")
        {
            $str.=" longtitle=\"" .
                  escape_string($component->{description}) . "\"";
        }
        if (($component->{command} || "") ne "")
        {
            my $cmd=$component->{command};
            # We must quadruple backslashes!
            $cmd =~ s%\\%\\\\\\\\%g;
            # But double quotes are escaped normally
            $cmd =~ s%\"%\\\"%g;
            $str.=" command=\"$cmd\"";
        }
        my $icon=CXMenu::get_unix_icon_path($component) ||
                 CXMenu::get_default_icon_path($component->{is_dir});
        $str.=" icon=\"" . escape_string($icon) . "\"";
        # Note: Debian menus cannot be localized

        if (defined $line)
        {
            $self->{lines}->[$line]=$str;
        }
        else
        {
            $self->{menus}->{$path}=@{$self->{lines}};
            push @{$self->{lines}}, $str;
        }
    }

    return $path;
}

sub install($$)
{
    my ($self, $components)=@_;

    # We don't support desktop icons
    my $menu=$components->[-1];
    return 1 if ($menu->{is_desktop});
    return 0 if (!$self->read_menu_file());

    # Note: Some update-menus plugins (e.g. the KDE one) don't take
    # advantage of the menu folder entries we create but some do
    # (e.g. the fvwm95 one or the KDE one on Mandrake). So we should
    # still create and specify icons for each intermediate menu folder.
    my $path="/";
    foreach my $component (@$components)
    {
        $path=$self->create_component($path, $component);
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
    }
    $self->{modified}=1;
    return 1;
}

sub query($$)
{
    my ($self, $components)=@_;
    return ($self->id(), "") if (!defined $components);

    # We don't support desktop icons
    my $menu=$components->[-1];
    return "" if ($menu->{is_desktop});
    return 0 if (!$self->read_menu_file());

    my $path=$menu->{path};
    return $self->id() if (defined $self->{menus}->{$menu->{path}});
    return "";
}

sub get_files($$)
{
    my ($self, $components)=@_;
    my $filename="$self->{menu}/cxmenu-$self->{tag}";
    return -f $filename ? [$filename] : [];
}

sub uninstall($$)
{
    my ($self, $components)=@_;

    # We don't support desktop icons
    my $menu=$components->[-1];
    return 1 if ($menu->{is_desktop});
    return 0 if (!$self->read_menu_file());

    # Always mark the parent folder for garbage collection
    $self->{garbage_collect}->{$menu->{dir}}=1;

    # Note: We don't remove lines from the array so we don't upset the
    # line numbers
    if ($menu->{is_dir})
    {
        cxlog("folder '$menu->{path}'\n");
        while (my ($item, $line)=each %{$self->{menus}})
        {
            next if ($item !~ /^\Q$menu->{path}\E/);
            cxlog(" removing line $line '$item'\n");
            $self->{lines}->[$line]=undef;
            delete $self->{menus}->{$item};
            $self->{modified}=1;
        }
    }
    else
    {
        cxlog("menu '$menu->{path}'\n");
        my $line=$self->{menus}->{$menu->{path}};
        if (defined $line)
        {
            cxlog(" removing line $line\n");
            $self->{lines}->[$line]=undef;
            delete $self->{menus}->{$menu->{path}};
            $self->{modified}=1;
        }
    }

    return 1;
}

# This function assumes that it is being called before any of the others
# which means it does not have to clean up 'filename', 'menus', etc.
sub removeall($$)
{
    my ($self, $pattern)=@_;

    if ($pattern eq "legacy")
    {
        $pattern="^" . CXUtils::get_product_id() . "(?:-[0-9a-f]+-[0-9a-f]+)?\$";
    }
    else
    {
        $pattern="^cxmenu-$pattern";
    }
    if (CXUtils::delete_files($self->{menu}, $pattern) > 0)
    {
        # Delete the parent directory if it's empty
        rmdir $self->{menu};
        $self->{update}=1;
    }
    if ($self->{old_menu} and CXUtils::delete_files($self->{old_menu}, $pattern) > 0)
    {
        # Delete the parent directory if it's empty
        rmdir $self->{old_menu};
        $self->{update}=1;
    }

    return 1;
}

sub gc_get_folder_status($$)
{
    my ($self, $path)=@_;

    cxlog("menus=[",join(":", keys %{$self->{menus}}),"]\n");
    return "in-use" if (grep m%^\Q$path/\E.$%, keys %{$self->{menus}});
    return "empty";
}

sub gc_delete_folder($$$)
{
    my ($self, $path)=@_;

    cxlog("deleting the '$path' directory\n");
    my $line=delete $self->{menus}->{"$path/"};
    if (defined $line)
    {
        cxlog(" 274 -> removing line $line\n");
        $self->{lines}->[$line]=undef;
        $self->{modified}=1;
    }
}

sub finalize($)
{
    my ($self)=@_;

    $self->SUPER::finalize();

    if ($self->{modified})
    {
        my $empty=1;
        foreach my $line (@{$self->{lines}})
        {
            if (defined $line)
            {
                $empty=0;
                last;
            }
        }
        if ($empty)
        {
            cxlog("CXMenuDebian deleting empty '$self->{filename}' file\n");
            # Delete the menu file
            if (-e $self->{filename} and !unlink $self->{filename})
            {
                cxerr("unable to delete '$self->{filename}': $!\n");
                return 0;
            }
            # Delete the parent directory if it's empty
            rmdir $self->{menu};
        }
        else
        {
            # Save the menu file
            if (!cxmkpath($self->{menu}))
            {
                cxerr("unable to create the '$self->{menu}' directory: $@\n");
                return 0;
            }
            my $fh;
            if (!open($fh, ">", $self->{filename}))
            {
                cxerr("unable to open '$self->{filename}' for writing: $!\n");
                return 0;
            }
            cxlog("CXMenuDebian writing to '$self->{filename}'\n");
            foreach my $line (@{$self->{lines}})
            {
                next if (!defined $line);
                print $fh "$line\n";
            }
            close($fh);
        }
        $self->{update}=1;
    }
    if ($self->{update} and !$self->{destdir})
    {
        # Make sure we only run one instance at a time (just to be safe).
        # See also CXAssocMandrake.pm.
        my $lock=CXUtils::cxlock("update-menus");
        cxsystem("update-menus");
        CXUtils::cxunlock($lock);
    }
    return 1;
}

return 1;
