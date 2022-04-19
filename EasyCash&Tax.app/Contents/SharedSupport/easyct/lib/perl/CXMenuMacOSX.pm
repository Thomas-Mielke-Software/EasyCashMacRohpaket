# (c) Copyright 2006-2008, 2010, 2014. CodeWeavers, Inc.
package CXMenuMacOSX;
use warnings;
use strict;

use CXLog;
use CXXMLDOM;
use CXPlist;
use CXMenu;
use base "CXMenu";


#####
#
# Folder helper functions
#
#####

sub get_mac_components($$)
{
    my ($self, $components)=@_;

    my $menu=@$components[-1];
    my $mac_root=$self->{$menu->{root}};
    if (!defined $mac_root)
    {
        $mac_root=[{ _mac_key    => "$self->{tag}/",
                     _mac_path   => "$self->{tag}/",
                     description => $ENV{CX_BOTTLE},
                     is_dir      => 1
                   },
                   { _mac_key    => "$menu->{root}/",
                     _mac_path   => "$self->{tag}/$menu->{root}/",
                     is_dir      => 1
                   }
                  ];
        $self->{$menu->{root}}=$mac_root;
    }

    my @mac_components=@$mac_root;
    if (!exists $menu->{_mac_path})
    {
        my $root="$menu->{tag}/$menu->{root}";
        foreach my $component (@$components)
        {
            # The trailing '/' is needed to separate the folder and menu
            # namespaces. It is also what identifies folders in the plist file.
            if ($component->{is_dir})
            {
                $component->{_mac_key}="$component->{name}/";
                $component->{_mac_path}="$root$component->{path}/";
            }
            else
            {
                $component->{_mac_key}="$component->{name}";
                $component->{_mac_path}="$root$component->{path}";
            }
        }
    }
    push @mac_components, @$components;
    return \@mac_components;
}

sub component_to_dict($$)
{
    my ($component, $dict)=@_;

    if ($component->{localize})
    {
        CXPlist::add_key_with_new_tag($dict, "Localize", "true");
    }
    if ($component->{description})
    {
        CXPlist::add_key_with_string($dict, "Description", $component->{description});
    }
    if ($component->{icon})
    {
        my $icon=CXMenu::get_mac_icon_path($component);
        if ($icon)
        {
            CXPlist::add_key_with_string($dict, "Icon", $icon);
            $icon =~ s!^\Q$ENV{WINEPREFIX}\E/!%WINEPREFIX%/!;
            $icon =~ s!^\Q$ENV{CX_ROOT}\E/!%CX_ROOT%/!;
            CXPlist::add_key_with_string($dict, "RobustIcon", $icon);
        }
    }
    if ($component->{command})
    {
        CXPlist::add_key_with_string($dict, "Command", $component->{command});
    }
    if ($component->{rawpath})
    {
        CXPlist::add_key_with_string($dict, "RawPath", $component->{rawpath});
    }
    if ($component->{arch})
    {
        CXPlist::add_key_with_string($dict, "Arch", $component->{arch});
    }
}

sub get_folder($$$$)
{
    my ($self, $parent, $mac_path, $mac_key)=@_;

    if (exists $self->{folders}->{$mac_path})
    {
        return $self->{folders}->{$mac_path};
    }

    my $children=$self->{children}->{$parent};
    if (!defined $children)
    {
        $children=CXPlist::get_value_by_name($parent, "Children");
        $self->{children}->{$parent}=$children;
    }
    my $folder=CXPlist::get_value_by_name($children, $mac_key) if (defined $children);
    $self->{folders}->{$mac_path}=$folder;
    return $folder;
}


#####
#
# XML file creation and parsing
#
#####

sub init_xml($$)
{
    my ($self)=@_;

    return $self->{xml} if (defined $self->{xml});
    $self->{xml}=0;

    my $xml;
    if (-f $self->{xml_file})
    {
        $xml=CXXMLDOM::parse_xml_file($self->{xml_file});
    }
    else
    {
        cxlog("Creating Mac OS X menu plist file\n");
        my $plist="<plist version=\"1.0\">\n" .
                "  <dict>\n" .
                "  </dict>\n" .
                "</plist>\n";
        $xml=CXXMLDOM::parse_xml_string($plist);
    }
    return 0 if (!$xml);

    # Now check that the basic structure of this XML file is correct
    my $plist=find_tag($xml, "plist");
    if (!$plist)
    {
        cxerr("unable to find the top plist tag in '$self->{xml_file}'\n");
        return 0;
    }

    my $tags_root=find_tag($plist, "dict");
    if (!$tags_root)
    {
        cxerr("unable to find the top dict tag in '$self->{xml_file}'\n");
        return 0;
    }

    $self->{xml}=$xml;
    $self->{plist}=$plist;
    $self->{tags_root}=$tags_root;
    $self->{children}->{$tags_root}=$tags_root;
    return 1;
}


#####
#
# Main
#
#####

sub detect($$$$)
{
    my ($class, $cxoptions, $cxconfig, $gui_info)=@_;
    return () if (!$gui_info->{macosx_on});
    # We don't do anything outside bottles
    return () if (!$cxoptions->{desktopdata} or $cxoptions->{ro_desktopdata});

    # Check for XML::DOM support
    my $err=CXXMLDOM::get_xml_load_error();
    if ($err)
    {
        cxerr("unable to use XML::DOM:\n$err\n");
        return  ();
    }

    my $self={
        tag         => $cxoptions->{tag},
        desktopdata => $cxoptions->{desktopdata},
        xml_file    => "$cxoptions->{desktopdata}/cxmenu/cxmenu_macosx.plist"
    };
    bless $self, $class;
    return ($self);
}

sub id($)
{
    return "CXMenuMacOSX/";
}

sub install($$)
{
    my ($self, $components)=@_;
    return 0 if (!$self->init_xml());

    my $in_cache=1;
    my $parent=$self->{tags_root};
    my $mac_components=$self->get_mac_components($components);
    foreach my $component (@$mac_components)
    {
        my $folder;
        $folder=$self->{folders}->{$component->{_mac_path}} if ($in_cache);
        if (!defined $folder)
        {
            $in_cache=undef;
            my $children=$self->{children}->{$parent};
            if (!defined $children)
            {
                $children=CXPlist::get_value_by_name($parent, "Children");
                $children=CXPlist::add_key_with_new_tag($parent, "Children", "dict") if (!defined $children);
                $self->{children}->{$parent}=$children;
            }
            $folder=CXPlist::get_value_by_name($children, $component->{_mac_key});
        }

        if (!defined $folder)
        {
            my $children=$self->{children}->{$parent};
            cxlog("creating $component->{_mac_path}\n");
            $folder=CXPlist::add_key_with_new_tag($children, $component->{_mac_key}, "dict");
            component_to_dict($component, $folder);
            $self->{folders}->{$component->{_mac_path}}=$folder;
        }
        elsif (!$component->{intermediate})
        {
            my $children=$folder->getParentNode();
            cxlog("recreating $component->{_mac_path}\n");

            # Overwrite the old properties
            my $new_folder=create_element($children->getOwnerDocument(), "dict");
            $children->replaceChild($new_folder, $folder);
            component_to_dict($component, $new_folder);

            if ($component->{is_dir})
            {
                # But keep the old children nodes, if any
                my $children=CXPlist::get_value_by_name($folder, "Children");
                if (defined $children)
                {
                    CXPlist::add_key_with_child($new_folder, "Children", $children);
                    $self->{children}->{$new_folder}=$children;
                }
            }

            $folder=$new_folder;
            $self->{folders}->{$component->{_mac_path}}=$folder;
        }
        $parent=$folder;
    }

    # Make sure our brand new (maybe empty) folder will not be
    # 'garbage collected' by finalize()
    my $menu=@$mac_components[-1];
    $self->{status}->{$menu->{_mac_path}}="in-use" if ($menu->{is_dir});

    $self->{modified}=1;
    return 1;
}

sub query($$)
{
    my ($self, $components)=@_;
    return ($self->id(), "") if (!defined $components);
    return "0" if (!$self->init_xml());

    my $parent=$self->{tags_root};
    my $mac_components=$self->get_mac_components($components);
    foreach my $component (@$mac_components)
    {
        my $folder=$self->get_folder($parent, $component->{_mac_path},
                                  $component->{_mac_key});
        return "" if (!defined $folder);
        $parent=$folder;
    }

    return $self->id();
}

sub get_files($$)
{
    my ($self, $components)=@_;
    # The XML file is inside the CrossOver bottle
    # but would not normally get packaged.
    return -f $self->{xml_file} ? [$self->{xml_file}] : [];
}

sub uninstall($$)
{
    my ($self, $components)=@_;
    return 0 if (!$self->init_xml());

    # Get hold of the folder
    my $folder;
    my $parent=$self->{tags_root};
    my $mac_components=$self->get_mac_components($components);
    foreach my $component (@$mac_components)
    {
        $folder=$self->get_folder($parent, $component->{_mac_path},
                                  $component->{_mac_key});
        return 1 if (!defined $folder);
        $parent=$folder;
    }

    # Delete it
    my $mac_path=$mac_components->[-1]->{_mac_path};
    cxlog("Deleting $mac_path\n");
    $parent=$folder->getParentNode();
    my $key=CXPlist::get_key_by_value($folder);
    remove_element($parent, $key);
    remove_element($parent, $folder);
    $self->{folders}->{$mac_path}=undef;
    $self->{modified}=1;

    # Always mark the parent folder for garbage collection
    $self->{garbage_collect}->{$mac_components->[-2]->{_mac_path}}=1;

    return 1;
}

sub removeall($$)
{
    my ($self, $pattern)=@_;

    if (-f $self->{xml_file})
    {
        cxlog("Deleting '$self->{xml_file}'\n");
        if (!unlink $self->{xml_file})
        {
            cxerr("unable to delete '$self->{xml_file}': $!\n");
            return 0;
        }
    }
    delete $self->{xml};

    return 1;
}

sub gc_get_folder_status($$)
{
    my ($self, $mac_path)=@_;

    my $path="";
    my $folder;
    my $parent=$self->{tags_root};
    foreach my $mac_key (split "/", $mac_path)
    {
        $path.="$mac_key/";
        $folder=$self->get_folder($parent, $path, $mac_key);
        if (!$folder)
        {
            cxlog("folder '$mac_path' has already been deleted\n");
            return undef;
        }
        $parent=$folder;
    }

    # Check for sub-folders
    my $children=$self->{children}->{$folder};
    $children=CXPlist::get_value_by_name($folder, "Children") if (!defined $children);
    return ("in-use", $folder) if ($children and find_tag($children, "key"));

    cxlog("mac_path=[$mac_path] empty\n");
    return ("empty", $folder);
}

sub gc_delete_folder($$$)
{
    my ($self, $mac_path, $folder)=@_;

    cxlog("Deleting $mac_path\n");
    my $parent=$folder->getParentNode();
    my $key=CXPlist::get_key_by_value($folder);
    remove_element($parent, $key);
    remove_element($parent, $folder);
    $self->{modified}=1;
}

sub finalize($)
{
    my ($self)=@_;
    return 0 if (!$self->{xml});

    $self->SUPER::finalize();

    if ($self->{modified})
    {
        if (find_tag($self->{tags_root}, "key"))
        {
            return CXXMLDOM::save_xml_file($self->{xml_file}, $self->{xml},
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple Computer//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n");
        }
        else
        {
            # The file is empty so let's just delete it
            if (-f $self->{xml_file})
            {
                cxlog("Deleting '$self->{xml_file}'\n");
                if (!unlink $self->{xml_file})
                {
                    cxerr("unable to delete '$self->{xml_file}': $!\n");
                    return 0;
                }
            }
            # Delete the parent directory if it is empty
            CXUtils::garbage_collect_subdirs($self->{desktopdata}, "/cxmenu", 1);
        }
    }
    else
    {
        cxlog("XML file '$self->{xml_file}' not modified\n");
    }
    return 1;
}

return 1;
