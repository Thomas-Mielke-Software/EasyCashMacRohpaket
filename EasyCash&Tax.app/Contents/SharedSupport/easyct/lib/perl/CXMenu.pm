# (c) Copyright 2005-2012, 2014. CodeWeavers, Inc.
package CXMenu;
use warnings;
use strict;
use CXLog;
use CXUtils;


#####
#
# Miscellaneous
#
#####

sub menu_to_lnk($)
{
    my ($menu)=@_;
    if ($menu =~ s!^StartMenu/!c:/Windows/Start Menu/!)
    {
        # Nothing to do
    }
    elsif ($menu =~ s!^StartMenu([._])([^/]+)/!!)
    {
        $menu=join("", demangle_string($2),
                       ($1 eq "." ? "/" : "/Start Menu/"),
                       $menu);
    }
    elsif ($menu =~ s!^Desktop/!c:/Windows/Desktop/!)
    {
        # Nothing to do
    }
    elsif ($menu =~ s!^Desktop([._])([^/]+)/!!)
    {
        $menu=join("", demangle_string($2),
                       ($1 eq "." ? "/" : "/Desktop/"),
                       $menu);
    }
    else
    {
        cxerr("unknown menu location '$menu'\n");
    }
    return $menu;
}

sub set_path_closure($$$)
{
    my ($hash, $path, $value)=@_;

    # We don't want any trailing slash
    delete $hash->{$path} if ($path =~ m%/$%);

    while (1)
    {
        last if ($path !~ s%/+[^/]*$%%);
        last if (exists $hash->{$path});
        $hash->{$path}=$value;
    }
}

sub wineshelllink2cxmenu($$$$$$)
{
    my ($ismenu, $root, $link, $path, $args, $icon)=@_;
    my $cxmenu;
    $@="";

    # Convert the .lnk path into a suitable menu name
    my $menu=($ismenu ? "StartMenu" : "Desktop");
    $root =~ s!\\+!/!g;
    if ($root !~ m!^c:/Windows/(Start Menu|Desktop)!i)
    {
        # Keep the exact location of the .lnk file,
        # otherwise we will not be able to run it later
        $menu .= "." . mangle_string($root);
    }
    $link =~ s!\\+!/!g;
    if ($link !~ s!^\Q$root/\E!/!i)
    {
        $@="the link location '$link' does not match the root location '$root'\n";
        return undef;
    }
    $menu.=$link;
    $cxmenu->{fullpath}=$menu;
    $cxmenu->{icon}=$icon;

    if ($path and $path =~ /\.exe$/i)
    {
        my $wmclass=$path;
        $wmclass =~ s%^.*[/\\]%%;
        $wmclass =~ tr/A-Z/a-z/;
        $cxmenu->{startupwmclass}=$wmclass;
    }
    if ($path and $path =~ s/\.exe$//i and !$args)
    {
        $path =~ s%^.*[/\\]%%;
        $path =~ s/ //g;
        $path =~ tr/A-Z/a-z/;
        # Blacklist some shortcut names
        if ($path !~ /(?:^(?:autorun|isuspm|start|unins|unvise)|~)/i and
            ($path ne "winword" or $menu !~ /iTunes/i) and
            ($path ne "winproj" or $menu !~ /Server Accounts/i))
        {
            $cxmenu->{shortcut}=$path;
        }
    }
    return $cxmenu;
}


#####
#
# Dealing with icons
#
#####

sub get_default_icon($)
{
    my ($is_dir)=@_;
    return $is_dir ? "cxmenu" : "crossover";
}

my %iconcache;
sub fill_icon_cache($)
{
    my ($root)=@_;
    if (!$iconcache{$root})
    {
        my @dirs=("");
        while (@dirs)
        {
            my $dir=shift @dirs;
            if (opendir(my $dh, "$root/$dir"))
            {
                # There is typically one directory per icon size:
                # hicolor/32x32/apps/
                my $size="";
                $size=$1 if ($dir =~ m%(?:^|/)([0-9]+x[0-9]+)/%);
                foreach my $dentry (readdir $dh)
                {
                    next if ($dentry =~ /^\.\.?$/);
                    my $path="$root/$dir$dentry";
                    if (-d $path)
                    {
                        push @dirs, "$dir$dentry/";
                    }
                    else
                    {
                        my $basename=$dentry;
                        $basename =~ s/\.(?:icns|png|xpm)$//i;
                        $iconcache{$root}->{$basename}->{$size}="$dir$dentry";
                    }
                }
                closedir($dh);
            }
        }
    }
}

sub get_icon_paths($$)
{
    my ($root, $basename)=@_;
    return $iconcache{$root}->{$basename};
}

sub get_mac_icon_path($)
{
    my ($component)=@_;
    return $component->{icon} if ($component->{icon} =~ m%^/%);

    my $path="$component->{icon_root}/$component->{icon}.icns";
    return $path if (-f $path);
    return undef;
}

sub get_unix_icon_path($)
{
    my ($component)=@_;
    return $component->{icon} if ($component->{icon} =~ m%^/%);

    fill_icon_cache($component->{icon_root});
    my $icons=get_icon_paths($component->{icon_root}, $component->{icon});

    # Try to pick the most appropriate size for these (old) menuing systems
    foreach my $size ('32x32', '48x48', '24x24', '16x16', '64x64', '256x256', '')
    {
        return "$component->{icon_root}/$icons->{$size}" if (exists $icons->{$size});
    }
    # We could try to find an icon with some odd size but that's too unlikely
    # to be worth the trouble.
    return undef;
}

sub get_default_icon_path($)
{
    my ($is_dir)=@_;
    my $component={icon_root => "$ENV{CX_ROOT}/share/icons",
                   icon => get_default_icon($is_dir)};
    return get_unix_icon_path($component);
}


#####
#
# XDG icon files
#
#####

my %installed_icons;

sub xdg_install_icons($$$)
{
    my ($xdgdir, $tag, $component)=@_;

    # No need to create icon files if we have an absolute path
    $component->{_icon}=$component->{icon};
    return if ($component->{_icon} =~ m%^/%);

    my $key="$tag/$component->{icon}$xdgdir";
    if (defined $installed_icons{$key})
    {
        # We just installed this icon so there's no need to redo it
        $component->{_icon}=$installed_icons{$key};
        return;
    }

    # Try the specified icon first
    my $root=$component->{icon_root};
    fill_icon_cache($root);
    my $icons=get_icon_paths($root, $component->{icon});
    if (!$icons)
    {
        cxwarn("found no icon file for '$component->{icon}' in '$root'\n");
        $component->{_icon}=get_default_icon($component->{is_dir});
        $root="$ENV{CX_ROOT}/share/icons";
        fill_icon_cache($root);
        $icons=get_icon_paths($root, $component->{_icon});
    }

    # Get a list of the corresponding icon files (one per size)
    my $installed;
    foreach my $size (keys %$icons)
    {
        # XDG ignores icons that are not placed in a size bucket
        next if ($size eq "");
        my $icon=$icons->{$size};
        next if ($icon !~ /\.(?:png|xpm)$/i);
        my $link="$xdgdir/icons/hicolor/$size/apps";
        if (!cxmkpath($link))
        {
            cxerr("unable to create '$link': $@\n");
            next;
        }
        $link.="/cxmenu-$tag-" . cxbasename($icon);
        if (!-f $link)
        {
            cxlog("Creating $link -> $root/$icon\n");
            if (!symlink("$root/$icon", $link))
            {
                cxwarn("unable to create the '$link' link: $!\n");
            }
        }
        $installed=1;
    }
    if ($installed)
    {
        $component->{_icon}="cxmenu-$tag-$component->{_icon}";
    }
    elsif ($icons->{""} =~ /\.(?:png|xpm)$/i)
    {
        # We can only use a relative path if we were able to install a
        # size-specific icon. Otherwise we must specify a full path.
        $component->{_icon}=$component->{icon_root} . "/" . $icons->{""};
    }
    else
    {
        # The generic icon was apparently not a valid Unix icon
        $component->{_icon}=get_default_icon_path($component->{is_dir});
    }
    $installed_icons{$key}=$component->{_icon};
}


sub xdg_get_icon_files($$$$)
{
    my ($destdir, $xdgdirs, $tag, $component)=@_;

    # If we have an absolute path, then we did not install that icon
    # and thus we should not return it.
    $component->{_icon}=$component->{icon};
    return () if ($component->{_icon} =~ m%^/%);

    # Try the specified icon first
    my $root=$component->{icon_root};
    fill_icon_cache($root);
    my $icons=get_icon_paths($root, $component->{icon});
    if (!$icons)
    {
        $component->{_icon}=get_default_icon($component->{is_dir});
        $root="$ENV{CX_ROOT}/share/icons";
        fill_icon_cache($root);
        $icons=get_icon_paths($root, $component->{_icon});
    }

    # Get a list of the corresponding icon files (one per size)
    my @files;
    for my $rawdir (@$xdgdirs)
    {
        my $dir="$destdir$rawdir";
        foreach my $size (keys %$icons)
        {
            # XDG ignores icons that are not placed in a size bucket
            next if ($size eq "");
            my $icon=$icons->{$size};
            next if ($icon !~ /\.(?:png|xpm)$/i);
            my $link="$dir/icons/hicolor/$size/apps/cxmenu-$tag-" . cxbasename($icon);
            push @files, $link if (-f $link);
        }
    }
    return \@files;
}


#####
#
# XDG .desktop files
#
#####

sub xdg_fill_desktop_entry($$$)
{
    my ($section, $component, $tags)=@_;

    $section->set("Encoding", "UTF-8");
    $section->set("Type", ($component->{is_dir} ? "Directory" : "Application"));
    $section->set("X-Created-By", $tags);
    $section->set("Categories", $component->{_categories}) if (defined $component->{_categories});
    $section->set("StartupNotify", "true");
    $section->set("StartupWMClass", $component->{startupwmclass}) if (defined $component->{startupwmclass});
    $section->set("Icon", $component->{_icon});
    if ($component->{command})
    {
        # Notes:
        # * The desktop file format specifies that percents must be doubled.
        # * Not specified there is that KDE is buggy and is unable to properly
        #   handle double quotes even if we try to escape them.
        # * The XDG desktop file format also specifies that escape sequences
        #   are supported and that backslashes must be escaped.
        my $exec=$component->{command};
        $exec =~ s/%/%%/g;
        $section->set("Exec", "$exec \%u");
    }
    $section->set("Name", "$component->{name}$component->{_creator}");
    $section->set("Comment", $component->{description}) if ($component->{description});

    if ($component->{localize})
    {
        # Translate the name and description in two passes
        # so the file looks nice.
        my $oldlang=CXUtils::cxgetlang();
        my $oldencoding=CXUtils::cxsetencoding("UTF-8");
        foreach my $locale (CXUtils::get_supported_locales())
        {
            CXUtils::cxsetlang($locale);
            # scripts2pot: ignore=message
            my $msgstr=cxgettext($component->{name});
            if ($msgstr ne "" and $msgstr ne $component->{name})
            {
                $section->set("Name[$locale]", "$msgstr$component->{_creator}");
            }
        }
        if ($component->{description})
        {
            foreach my $locale (CXUtils::get_supported_locales())
            {
                CXUtils::cxsetlang($locale);
                # scripts2pot: ignore=message
                my $msgstr=cxgettext($component->{description});
                if ($msgstr ne "" and $msgstr ne $component->{description})
                {
                    $section->set("Comment[$locale]", $msgstr);
                }
            }
        }
        CXUtils::cxsetlang($oldlang);
        CXUtils::cxsetencoding($oldencoding);
    }
}

sub xdg_create_desktop_file($$)
{
    my ($filename, $component)=@_;

    # Create the desktop file from scratch
    require CXRWConfig;
    my $desktop=CXRWConfig->new(undef, "xdg", "");
    cxlog("Creating '$filename'\n");
    $desktop->set_filename($filename);
    $desktop->set_shebang("/usr/bin/env xdg-open");

    my $section=$desktop->append_section("Desktop Entry");
    xdg_fill_desktop_entry($section, $component, $component->{tag});

    if (!$desktop->save())
    {
        cxerr("unable to save '$filename': $!\n");
        return undef;
    }
    chmod(0777 & ~umask(), $filename);
    return $desktop;
}


#####
#
# XDG .directory files
#
#####

sub xdg_create_directory($$$)
{
    my ($filename, $component, $save)=@_;

    cxlog("Creating '$filename'\n");
    require CXRWConfig;
    my $directory=CXRWConfig->new($filename, "xdg", "");
    my $section=$directory->get_section("Desktop Entry");
    my %tags;
    if ($section)
    {
        my $created_by=$section->get("X-Created-By");

        # Don't tag non-CrossOver menus
        return $directory if (!defined $created_by);

        # Recreate the directory from scratch, only preserve the
        # X-Created-By field
        map { $tags{$_}=1; } split /;+/, $created_by;
        if (!$component->{intermediate})
        {
            $directory->remove_all();
            $section=undef;
        }
    }
    elsif (!$component->{intermediate})
    {
        # Reset the file, it's ours now
        $directory->remove_all();
    }
    elsif (-f "$filename")
    {
        cxerr("unknown format for '$filename'\n");
        return undef;
    }
    $tags{$component->{tag}}=1;
    my $created_by=join(";", sort keys %tags);

    if (!$section)
    {
        $section=$directory->append_section("Desktop Entry");
        xdg_fill_desktop_entry($section, $component, $created_by);
    }
    else
    {
        $section->set("X-Created-By", $created_by);
    }
    if ($save and !$directory->save())
    {
        cxerr("unable to save '$filename': $!\n");
    }
    return $directory;
}


#####
#
# The CXMenu base class
#
#####


# When creating menus, intermediate folders are created implicitly. This
# functions is responsible for 'garbage collecting' them when they become
# empty.
#
# In order to call this function a class must setup a list of folder paths
# to be garbage collected in $self->{garbage_collect} and a list of folder
# path status in $self->{status}.
#
# It must also implement the following helper functions:
# * ($status, $data)=$self->gc_get_status($path);
# * $self->gc_delete($path, $data)
# * $self->gc_untag($path, $data)
#
# The status can be one of the following:
# * empty
#   The folder does not contain any sub-folder or menu and thus can be deleted
#
# * non-empty
#   The folder still contains menus or sub-folders although none of them
#   belong to the current bottle. So we can remove the bottle's tag but we
#   must not delete the folder.
#
# * in-use
#   The folder contains at least one menu or sub-folder belonging to the
#   current bottle. This means it must not be deleted and that the bottle's
#   tag must not be removed either.
#
# * alien
#   This folder does not belong to us at all. There is no tag to remove (by
#   definition) and we should not delete the folder.
sub garbage_collect($)
{
    my ($self)=@_;

    my $garbage_collect=$self->{garbage_collect};
    return if (!$garbage_collect or !%$garbage_collect);

    # If a folder is marked for garbage collection,
    # then all its parents should be too
    foreach my $path (sort { $b cmp $a } keys %$garbage_collect)
    {
        CXMenu::set_path_closure($garbage_collect, $path, 1);
    }
    # For debug:
    # cxlog("Initial garbage collection list:\n");
    # map { cxlog("  $_\n") } sort { $b cmp $a } keys %$garbage_collect;

    # If a folder is 'in-use', then all its parents are 'in-use' too
    # In fact the more correct status may be 'alien' but it does not
    # matter because we won't touch them in either case
    my $status=$self->{status};
    foreach my $path (sort { $b cmp $a } keys %$status)
    {
        CXMenu::set_path_closure($status, $path, "in-use");
    }
    # For debug:
    # cxlog("Initial status:\n");
    # map { cxlog("  $_ -> in-use\n") } sort { $b cmp $a } keys %$status;

    # Now do the garbage collection itself
    foreach my $path (sort { $b cmp $a } keys %$garbage_collect)
    {
        cxlog("garbage_collect: considering '$path'\n");
        if (exists $status->{$path})
        {
            # If a folder already has a status it is necessarily
            # 'in-use' which means we should not touch it
            cxlog(" -> already $status->{$path}\n");
            next;
        }
        my ($st, $data)=$self->gc_get_folder_status($path);
        next if (!defined $st);
        $status->{$path}=$st;
        cxlog(" -> $st\n");
        if ($st eq "empty")
        {
            # Delete the folder altogether
            $self->gc_delete_folder($path, $data);
        }
        elsif ($st eq "non-empty")
        {
            # Just untag the folder
            $self->gc_untag_folder($path, $data);
        }
        elsif ($st eq "in-use")
        {
            CXMenu::set_path_closure($status, $path, "in-use");
        }
    }
}

sub finalize($)
{
    my ($self)=@_;
    $self->garbage_collect();
    return 1;
}

return 1;
