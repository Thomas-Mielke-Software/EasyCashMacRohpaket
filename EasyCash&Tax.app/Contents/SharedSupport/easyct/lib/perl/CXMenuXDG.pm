# (c) Copyright 2005-2014. CodeWeavers, Inc.
package CXMenuXDG;
use warnings;
use strict;

use CXLog;
use CXUtils;
use CXXMLDOM;
use CXMenu;
use base "CXMenu";



#####
#
# Folder helper functions
#
#####

sub get_root_menu($$)
{
    my ($self, $component)=@_;

    if (!$self->{root_subname} or
        $self->{root_allowed}->{$component->{_xname}})
    {
        $component->{_xpath}="/$component->{_xname}";
        return $self->{root_menu};
    }

    if (!$self->{root_submenu})
    {
        $self->{root_submenu}=get_child_by_name($self->{root_menu}, "Menu", $self->{root_subname});
        if (!$self->{root_submenu})
        {
            $self->{root_submenu}=add_new_element($self->{root_menu}, "Menu");
            add_new_element($self->{root_submenu}, "Name", $self->{root_subname});
        }
    }
    $component->{_xpath}="/$self->{root_subname}/$component->{_xname}";
    return $self->{root_submenu};
}

sub get_xpath($$)
{
    my ($self, $path)=@_;

    my $xpath=$path;
    if (defined $self->{root_subname})
    {
        my $topmenu=$xpath;
        $topmenu=~ s!^/([^/]+)(?:/.*)?$!$1!;
        if (!$self->{root_allowed}->{$topmenu})
        {
            $xpath="/$self->{root_subname}$xpath";
        }
    }
    cxlog("xpath='$xpath'\n");

    return $xpath;
}

sub get_folder_by_xpath($$)
{
    my ($self, $xpath)=@_;

    my $folder=$self->{folders}->{$xpath};
    # Check the parent node to verify that the folder has not been deleted
    return $folder if ($folder and $folder->getParentNode());

    $folder=get_tag_by_path($self->{root_menu}, "Menu", $xpath);
    # $self->{folders} also serves as a negative cache
    $self->{folders}->{$xpath}=$folder;
    return $folder;
}

sub get_xdg_basename($$)
{
    my ($self, $path)=@_;

    $path =~ s!/$!!;
    return "cxmenu-$self->{tag}-" . CXUtils::base32(CXUtils::hash_string($path), 7);
}


sub create_folder($$$)
{
    my ($self, $parent, $component)=@_;
    cxlog("create_folder($component->{_xpath})\n");

    my $folder=$self->{folders}->{$component->{_xpath}};
    if (!defined $folder)
    {
        $folder=get_child_by_name($parent, "Menu", $component->{_xname});
    }

    # Update the XML tree
    my $basename=$self->get_xdg_basename($component->{path});
    my $new_folder;
    if (!defined $folder)
    {
        # Add a new <Menu> tag
        my $pos=get_child($parent, "Menu");
        $folder=add_new_element($parent, "Menu", undef, $pos);
        # gnome-panel < 2.10 (e.g. Fedora Core 2 and 3) is confused if it
        # finds a '%' in the XML file. Using the XML character entity
        # instead does not help. Furthermore the Name field in the
        # .directory file will override the XML <Name> tag anyway, so let's
        # just use the mangled folder name.
        add_new_element($folder, "Name", $component->{_xname});
        add_new_element($folder, "Directory", "$basename.directory");

        if ($self->{hidden_hack})
        {
            # KDE 3.5.1 is buggy and won't show folders that have no menu entry
            # and a single sub-folder. So we always add an empty '#Hidden'
            # folder:
            # - The '#' guarantees there won't be a name collision with a real
            #   mangled folder name.
            # - Because that folder is empty it will not be shown.
            # - Folders will always have at least two entries and thus will
            #   always be shown.
            # - However this also disables KDE's 'collapsing' feature for
            #   single-entry folders and thus we only enable this hack when
            #   needed.
            my $hidden=add_new_element($folder, "Menu");
            add_new_element($hidden, "Name", "#Hidden");
        }
        my $inctag=add_new_element($folder, "Include");
        add_new_element($inctag, "Category", "X-$basename");

        $self->{folders}->{$component->{_xpath}}=$folder;
        $self->{modified}=1;
        $new_folder=1;
    }

    # Update or create the .directory file
    my $folder_dir="$self->{xdg_dir}/desktop-directories";
    my $filename="$folder_dir/$basename.directory";
    if ($new_folder or !$component->{intermediate} or !-f $filename)
    {
        if (!cxmkpath($folder_dir))
        {
            cxerr("unable to create the '$folder_dir' directory: $@\n");
            return 0;
        }
        # (Re)Create the corresponding directory file (from scratch)
        # xdg_create_directory() takes care of everything, we just need
        # to figure out the filename
        CXMenu::xdg_create_directory($filename, $component, 1);
    }

    return $folder;
}

sub delete_folder($$$;$)
{
    my ($self, $folder, $xpath, $detach)=@_;

    # Delete that folder's directory and desktop files
    my $directory=get_child($folder, "Directory");
    if ($directory)
    {
        # Computing the path from the xpath is tricky. Fortunately for our menus
        # the <Directory> tag contains the basename so we don't need the path.
        # If <Directory> does not look like a basename then it must be the
        # root_menu or root_submenu and they don't have desktop or directory
        # files anyway.
        my $basename=get_cdata($directory);
        $basename =~ s/\.directory$//;
        if ($basename =~ /^cxmenu-/)
        {
            for my $rawdir (@{$self->{xdg_dirs}})
            {
                my $dir="$self->{destdir}$rawdir";
                # The desktop files
                CXUtils::delete_files("$dir/applications", "$basename-.*\\.desktop\$");
                # And the directory file
                my $filename="$dir/desktop-directories/$basename.directory";
                if (-f $filename)
                {
                    cxlog("Deleting '$filename'\n");
                    cxwarn("unable to delete '$filename': $!\n") if (!unlink $filename);
                }
            }
        }
    }

    # Then recursively delete the subfolders. We have to do that to get rid of
    # their .desktop and .directory files.
    my $child=$folder->getFirstChild();
    while (defined $child)
    {
        my $tag=$child->getNodeName();
        if ($tag eq "Menu")
        {
            my $name=get_cdata(get_child($child, "Name"));
            $self->delete_folder($child, "$xpath/$name");
        }
        $child=$child->getNextSibling();
    }

    # Delete the <Menu> tag
    remove_element($folder->getParentNode(), $folder) if ($detach);
    delete $self->{folders}->{$xpath};
    $self->{modified}=1;
}


#####
#
# XDG XML file creation and parsing
#
#####

sub setup_default_merge_dir($)
{
    my ($self)=@_;
    my $merge_dir=$self->{menu};
    $merge_dir =~ s/\.menu$/-merged/;
    # Override the existing merge_dir if any
    $self->{merge_dir}=$merge_dir;
    push @{$self->{merge_dirs}}, $merge_dir;
}

sub get_xdg_config($$)
{
    my ($self)=@_;
    return if (defined $self->{root_name});

    # Read the master XML file to extract configuration information. Because
    # this is a configuration file we must read the real file, even if it is
    # outside destdir.
    my $filename=$self->{menu};
    $filename=$self->{master_menu} if (!-f $filename);
    if (-f $filename)
    {
        my $xml=CXXMLDOM::parse_xml_file($filename);
        if ($xml)
        {
            my $root_menu=find_tag($xml, "Menu");
            my $child=$root_menu->getFirstChild();
            while (defined $child)
            {
                my $tag=$child->getNodeName();
                if ($tag eq "Name")
                {
                    $self->{root_name}=get_cdata($child);
                }
                elsif ($tag eq "DefaultMergeDirs")
                {
                    cxlog("found <DefaultMergeDirs>\n");
                    $self->setup_default_merge_dir();
                }
                elsif ($tag eq "MergeDir")
                {
                    my $merge_dir=get_cdata($child);
                    if ($merge_dir)
                    {
                        if ($merge_dir !~ m%^/%)
                        {
                            my $dir=cxdirname($self->{menu});
                            $merge_dir="$dir/$merge_dir";
                        }
                        # Must check the real directory here so we know what to
                        # create in destdir
                        if (!-d $merge_dir)
                        {
                            cxlog("the '$merge_dir' MergeDir does not exist. Ignoring it.\n");
                        }
                        elsif (!-w $merge_dir)
                        {
                            cxlog("the '$merge_dir' MergeDir is not writable. Ignoring it.\n");
                        }
                        else
                        {
                            if (!defined $self->{merge_dir})
                            {
                                $self->{merge_dir}=1;
                            }
                            push @{$self->{merge_dirs}}, $merge_dir;
                        }
                    }
                }
                elsif ($tag eq "Layout")
                {
                    cxlog("found <Layout>\n");
                    my $lspec=$child->getFirstChild();
                    while (defined $lspec)
                    {
                        $tag=$lspec->getNodeName();
                        if ($tag eq "Merge")
                        {
                            my $type=$lspec->getAttribute("type") || "";
                            cxlog("type=$type\n");
                            if ($type =~ /^(menus|all)$/i)
                            {
                                # We won't have trouble adding our menus
                                delete $self->{root_subname};
                                delete $self->{root_allowed};
                                last;
                            }
                        }
                        elsif ($tag eq "Menuname")
                        {
                            my $name=get_cdata($lspec);
                            if ($name)
                            {
                                if (!defined $self->{root_subname})
                                {
                                    $self->{root_subname}=$name;
                                }
                                $self->{root_allowed}->{$name}=1;
                            }
                        }
                        $lspec=$lspec->getNextSibling();
                    }
                    if ($self->{root_subname})
                    {
                        cxlog("sub root='$self->{root_subname}'\n");
                        cxlog("allowed root directories:\n  ",
                              join("\n  ", keys %{$self->{root_allowed}}), "\n");
                    }
                }
                $child=$child->getNextSibling();
            }
        }
    }
    $self->{root_name} ||= "Applications";
    $self->setup_default_merge_dir() if (!defined $self->{merge_dir});
}


sub init_xml($$)
{
    my ($self)=@_;

    return $self->{xml} if (defined $self->{xml_file});
    $self->get_xdg_config();
    $self->{xml_file}="$self->{destdir}$self->{merge_dir}/cxmenu-$self->{tag}.menu";

    my $xml;
    if (-f $self->{xml_file})
    {
        $xml=CXXMLDOM::parse_xml_file($self->{xml_file});
    }
    else
    {
        cxlog("Creating XDG menu file\n");
        my $xdg="<Menu>\n" .
                "  <Name>$self->{root_name}</Name>\n" .
                "</Menu>\n";
        $xml=CXXMLDOM::parse_xml_string($xdg);
    }
    return 0 if (!$xml);
    $self->{xml}=$xml;

    # Make sure we have a root menu
    $self->{root_menu}=find_tag($xml, "Menu");
    if (!$self->{root_menu})
    {
        $self->{root_menu}=add_new_element($xml, "Menu");
        add_new_element($self->{root_menu}, "Name", $self->{root_name});
    }

    return 1;
}


#####
#
# Main
#
#####

sub new($$$$$)
{
    my ($class, $cxoptions, $gui_info, $menu, $master_menu)=@_;

    my $self={
        tag              => $cxoptions->{tag},
        destdir         => $cxoptions->{destdir},
        desktopdata      => $cxoptions->{desktopdata},
        ro_desktopdata   => $cxoptions->{ro_desktopdata},
        menu             => $menu,
        master_menu      => $master_menu,
        xdg_dir          => $gui_info->{xdg_preferred_data},
    };
    if ($gui_info->{preferred_scope} eq "private")
    {
        $self->{xdg_dirs}=[$gui_info->{xdg_preferred_data}];
    }
    else
    {
        $self->{xdg_dirs}=[grep {$_ ne ""} split /:+/, $gui_info->{xdg_data_dirs}];
    }

    if (($gui_info->{kde_version} || "") =~ /^3\.5\./)
    {
        $self->{hidden_hack}=1;
    }

    bless $self, $class;
    return $self;
}

sub detect($$$$)
{
    my ($class, $cxoptions, $cxconfig, $gui_info)=@_;
    return () if (!$gui_info->{xdg_menu_on});

    # Check for XML::DOM support
    my $err=CXXMLDOM::get_xml_load_error();
    if ($err)
    {
        cxerr("unable to use XML::DOM:\n$err\n");
        return  ();
    }

    # Notes:
    # - CXMenuXDG does not handle the XDG desktop icons as these
    #   have nothing in common with the regular XDG menus.
    # - Also, each XDG menu instance could in theory share its files
    #   including the XML file with a simple symbolic link in the right place.
    #   However, each instance must also be independent. That is, it should be
    #   possible to disable an instance while still creating the others,
    #   and uninstalling a given menu in an instance should not delete the
    #   corresponding menu in the others. This means either introducing
    #   complex usage tracking (slowing things down too), or duplicating the
    #   menus and keeping the current relatively simple code at the cost of
    #   doing the same work twice when multiple instances are present.
    #   The latter solution was chosen.
    # - We may also have independent sets of global XDG menus that all
    #   correspond to a single set of user XDG menus. So detect duplicate
    #   xdg_preferred_menu* values and only create one CXMenuXDG instance for
    #   them. Note that this means we will only read the settings of one of
    #   the global .menu files. Hopefully they will all be interchangeable.
    my %seen;
    my @selves;
    for (my $i=1; exists $gui_info->{"xdg_preferred_menu$i"}; $i++)
    {
        my $preferred=$gui_info->{"xdg_preferred_menu$i"};
        next if ($seen{$preferred});
        $seen{$preferred}=1;
        push @selves, new($class, $cxoptions, $gui_info,
                          $preferred, $gui_info->{"xdg_global_menu$i"});
    }
    return @selves;
}

sub id($)
{
    my ($self)=@_;
    my $id="CXMenuXDG/$self->{menu}";
    $id =~ s%/+%/%g;
    return $id;
}

sub install($$)
{
    my ($self, $components)=@_;

    my $menu=@$components[-1];
    return 1 if ($menu->{is_desktop});
    return 0 if (!$self->init_xml());

    if (!defined $menu->{xdgcategories} and $self->{menu})
    {
        # Create the folder the menu entry is supposed to be in
        my ($folder, $xpath);
        foreach my $component (@$components)
        {
            $component->{_xname}=$component->{name};
            if (!$folder)
            {
                $folder=$self->get_root_menu($component);
                $xpath=$component->{_xpath};
            }
            else
            {
                $xpath="$xpath/$component->{_xname}";
                $component->{_xpath}=$xpath;
            }
            $component->{_creator}="";
            last if (!$component->{is_dir});
            CXMenu::xdg_install_icons($self->{xdg_dir}, $self->{tag}, $component);
            $folder=$self->create_folder($folder, $component);
            return 0 if (!defined $folder);
        }
    }
    else
    {
        # No need to create a folder. The menuing system will place the menu
        # entry according to its XDG category.
        $menu->{_xpath}=$menu->{path};
        $menu->{_xname}=$menu->{name};
        $menu->{_creator}="";
    }

    CXMenu::xdg_install_icons($self->{xdg_dir}, $self->{tag}, $menu);
    if ($menu->{is_dir})
    {
        # Make sure our brand new (maybe empty) folder will not be
        # 'garbage collected' by finalize()
        $self->{status}->{$menu->{_xpath}}="in-use";
    }
    else
    {
        my $xdir=cxdirname($menu->{_xpath});
        $self->{status}->{$xdir}="in-use";

        # Create the desktop file
        my $apps_dir="$self->{xdg_dir}/applications";
        if (!cxmkpath($apps_dir))
        {
            cxerr("unable to create the '$apps_dir' directory: $@\n");
            return 0;
        }
        my $basename=$self->get_xdg_basename($menu->{dir});
        $menu->{_categories}=$menu->{xdgcategories} || "X-$basename;";
        $menu->{_creator}=" (" . $self->id() . ")" if ($ENV{CX_TAGALL});
        CXMenu::xdg_create_desktop_file("$apps_dir/$basename-$menu->{_xname}.desktop", $menu);
    }

    return 1;
}

sub query($$)
{
    my ($self, $components)=@_;
    return ($self->id(), "") if (!defined $components);

    my $menu=@$components[-1];
    return "" if ($menu->{is_desktop});
    return "0" if (!$self->init_xml());

    # Check that everything is in place in the XML file
    my $dir=$menu->{is_dir} ? $menu->{path} : $menu->{dir};
    $dir =~ s%/+$%%;
    my $basename=$self->get_xdg_basename($dir);
    if (!defined $menu->{xdgcategories})
    {
        my $xdir=$self->get_xpath($dir);
        my $folder=$self->get_folder_by_xpath($xdir);
        return "" if (!$folder);
        my $include=get_child($folder, "Include");
        return "" if (!$include);
        my $category=get_child($include, "Category");
        return "" if (!$category or get_cdata($category) ne "X-$basename");
    }

    # Then check the presence of the .desktop or .directory file
    my $filename=$menu->{is_dir} ?
        "desktop-directories/$basename.directory" :
        "applications/$basename-$menu->{name}.desktop";
    for my $dir (@{$self->{xdg_dirs}})
    {
        return $self->id() if (-f "$self->{destdir}$dir/$filename");
    }
    return "";
}

sub get_files($$)
{
    my ($self, $components)=@_;
    return [] if (!defined $components);

    my $menu=@$components[-1];
    return [] if ($menu->{is_desktop});

    my @files;
    $self->get_xdg_config();
    foreach my $mdir (@{$self->{merge_dirs}})
    {
        my $filename="$self->{destdir}$mdir/cxmenu-$self->{tag}.menu";
        push @files, $filename if (-f $filename);
    }
    push @files, @{CXMenu::xdg_get_icon_files($self->{destdir}, $self->{xdg_dirs}, $self->{tag}, $menu)};

    my $dir=$menu->{is_dir} ? $menu->{path} : $menu->{dir};
    $dir =~ s%/+$%%;
    my $basename=$self->get_xdg_basename($dir);
    my $filename=$menu->{is_dir} ?
        "desktop-directories/$basename.directory" :
        "applications/$basename-$menu->{name}.desktop";
    for my $dir (@{$self->{xdg_dirs}})
    {
        my $fullpath="$self->{destdir}$dir/$filename";
        push @files, $fullpath if (-f $fullpath);
    }
    return \@files;
}

sub uninstall($$)
{
    my ($self, $components)=@_;

    my $menu=@$components[-1];
    return 1 if ($menu->{is_desktop});
    return 0 if (!$self->init_xml());

    my $dir=$menu->{is_dir} ? $menu->{path} : $menu->{dir};
    $dir =~ s%/+$%%;

    # Always mark the parent folder for garbage collection
    # Note that it has to be an xpath in order to take into account the
    # potential 'root_submenu' (see get_root_menu()).
    my $xdir=$self->get_xpath($dir);
    my $xparent=($menu->{is_dir} ? cxdirname($xdir) : $xdir);
    $self->{garbage_collect}->{$xparent}=1;

    if ($menu->{is_dir})
    {
        my $folder=$self->get_folder_by_xpath($xdir);
        return 1 if (!$folder);
        $self->delete_folder($folder, $xdir, 1);
    }
    else
    {
        my $basename=$self->get_xdg_basename($dir);
        for my $dir (@{$self->{xdg_dirs}})
        {
            my $filename="$self->{destdir}$dir/applications/$basename-$menu->{name}.desktop";
            if (-f $filename)
            {
                cxlog("Deleting '$filename'\n");
                if (!unlink $filename)
                {
                    cxerr("unable to delete '$filename': $!\n");
                    return 0;
                }
            }
        }
    }

    return 1;
}

sub removeall($$)
{
    my ($self, $pattern)=@_;
    $self->get_xdg_config();

    my $xdg_pattern;
    if ($pattern eq "legacy")
    {
        my $legacy_dir="$ENV{CX_ROOT}/support/xdg-legacy-menus";
        if (-d $legacy_dir)
        {
            cxlog("Deleting the '$legacy_dir' directory\n");
            require File::Path;
            if (!File::Path::rmtree($legacy_dir))
            {
                cxerr("unable to delete the '$legacy_dir' directory: $!\n");
            }
        }
        $xdg_pattern="^cxlegacy";
    }
    else
    {
        $xdg_pattern="^cxmenu-$pattern";
        $xdg_pattern.=".*" if ($xdg_pattern !~ s/\$$//);
    }

    foreach my $mdir (@{$self->{merge_dirs}})
    {
        my $dir="$self->{destdir}$mdir";
        next if (!-d $dir);
        if (!-w $dir)
        {
            cxlog("skipping read-only '$dir' directory\n");
            next;
        }
        CXUtils::delete_files($dir, "$xdg_pattern\\.menu");
    }

    for my $rawdir (@{$self->{xdg_dirs}})
    {
        my $dir="$self->{destdir}$rawdir";
        if (-d "$dir/applications")
        {
            CXUtils::delete_files("$dir/applications", "$xdg_pattern-.*\\.desktop\$");
        }
        if (-d "$dir/desktop-directories")
        {
            CXUtils::delete_files("$dir/desktop-directories", "$xdg_pattern-.*\\.directory\$");
        }
        if (-d "$dir/icons")
        {
            # Linux distributions ship empty icon directories so don't garbage
            # collect them.
            CXUtils::delete_files("$dir/icons", "$xdg_pattern-.*\\.(?:png|xpm)\$", 1, 0);
        }
    }

    return 1 if ($self->{ro_desktopdata});

    # Remove the directory trees where earlier CXMenuXDG versions
    # were storing the .desktop and .directory files
    my $cxdata_dir="xdg-" . cxbasename($self->{menu});
    $cxdata_dir =~ s/\.menu$//;

    if ($self->{tag} and "cxmenu-$self->{tag}" =~ /$xdg_pattern$/)
    {
        my $dir="$self->{desktopdata}/cxmenu/$cxdata_dir";
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
        CXBottle::removeall_desktopdata_dirs($pattern, "/cxmenu/$cxdata_dir");
    }

    return 1;
}

sub gc_get_folder_status($$)
{
    my ($self, $xpath)=@_;
    my $folder=$self->get_folder_by_xpath($xpath);
    if (!$folder)
    {
        cxlog("folder '$xpath' has already been deleted\n");
        return undef;
    }

    # Check for menu entries and sub-folders
    my $basename="";
    my $child=$folder->getFirstChild();
    while (defined $child)
    {
        my $tag=$child->getNodeName();
        if ($tag eq "Menu")
        {
            my $text=get_child($child, "Name");
            if (get_cdata($text) ne "#Hidden")
            {
                cxlog(" -> found a sub-folder\n");
                return ("in-use", $folder);
            }
        }
        elsif ($tag eq "Directory")
        {
            $basename=get_cdata($child);
            $basename =~ s/\.directory$//;
        }
        $child=$child->getNextSibling();
    }

    # Check if there are .desktop files in this folder
    if ($basename =~ /^cxmenu-/)
    {
        for my $dir (@{$self->{xdg_dirs}})
        {
            if (opendir(my $dh, "$self->{destdir}$dir/applications"))
            {
                foreach my $dentry (readdir $dh)
                {
                    if ($dentry =~ /^\Q$basename\E-.*\.desktop$/)
                    {
                        # Although this desktop file corresponds to a menu
                        # entry which originally was in this folder, it may
                        # have an XDG category that puts it elsewhere. This
                        # will just delay, not prevent the deletion of this
                        # folder a bit so we'll ignore this.
                        closedir($dh);
                        cxlog(" -> found a menu entry\n");
                        return ("in-use", $folder);
                    }
                }
                closedir($dh);
            }
        }
    }

    cxlog(" -> empty\n");
    return ("empty", $folder);
}

sub gc_delete_folder($$$)
{
    my ($self, $xpath, $folder)=@_;
    $self->delete_folder($folder, $xpath, 1);
}

sub finalize($)
{
    my ($self)=@_;
    return 1 if (!$self->{xml});

    $self->SUPER::finalize();

    if ($self->{modified})
    {
        if (find_tag($self->{xml}, "Menu"))
        {
            my $dir=cxdirname($self->{xml_file});
            my $target=readlink($dir);
            if (defined $target and $target !~ m%/%)
            {
                # On Mint 17 Cinnamon's '-merged' directory is a symbolic link
                # to the GNOME one which may not exist yet. So try to create it,
                # just in case.
                $target=cxdirname($dir) . "/$target";
                mkdir($target);
            }

            return CXXMLDOM::save_xml_file($self->{xml_file}, $self->{xml},
                "<!DOCTYPE Menu PUBLIC \"-//freedesktop//DTD Menu 1.0//EN\" \"http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd\">\n");
        }
        else
        {
            # The file is empty so let's just delete it
            if (-f $self->{xml_file})
            {
                cxlog("Deleting '$self->{xml_file}'\n");
                if (!unlink "$self->{xml_file}")
                {
                    cxerr("unable to delete '$self->{xml_file}': $!\n");
                    return 0;
                }
            }
        }
    }
    else
    {
        cxlog("XML file '$self->{xml_file}' not modified\n");
    }
    return 1;
}

return 1;
