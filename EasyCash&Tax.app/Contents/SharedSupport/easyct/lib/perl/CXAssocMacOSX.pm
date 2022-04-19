# (c) Copyright 2006-2008, 2010, 2014. CodeWeavers, Inc.
package CXAssocMacOSX;
use warnings;
use strict;

use CXLog;
use CXXMLDOM;
use CXPlist;
use CXAssoc;
use base "CXAssoc";


#####
#
# Folder helper functions
#
#####

sub get_mac_assoc_components($$$$)
{
    my ($self, $assoc, $root_key, $root_name)=@_;

    my $mac_root=$self->{$root_key};
    if (!defined $mac_root)
    {
        $mac_root=[{ _mac_key    => "$self->{tag}/",
                     _mac_path   => "$self->{tag}/",
                     description => $ENV{CX_BOTTLE},
                     is_dir      => 1
                   },
                   { _mac_key    => "$root_name/",
                     _mac_path   => "$self->{tag}/$root_name/",
                     is_dir      => 1
                   }
                  ];
        $self->{$root_key}=$mac_root;
    }

    my @mac_components=@$mac_root;
    if (!exists $assoc->{_mac_path})
    {
        $assoc->{_mac_key}="$assoc->{id}";
        $assoc->{_mac_path}="$self->{tag}/$root_name/$assoc->{id}";
        $assoc->{is_dir}=0;
    }
    push @mac_components, $assoc;
    return \@mac_components;
}

sub get_mac_eassoc_components($$)
{
    my ($self, $eassoc)=@_;

    if (!exists $eassoc->{_mac_icon})
    {
        $eassoc->{_mac_icon}=CXAssoc::get_icon($eassoc->{icon});
    }
    if (!exists $eassoc->{_mac_mimetype})
    {
        $eassoc->{_mac_mimetype}=$eassoc->{emime}->{mimetype};
    }

    return $self->get_mac_assoc_components($eassoc, "eassoc_root", "Extension Associations");
}

sub get_mac_massoc_components($$)
{
    my ($self, $massoc)=@_;

    return $self->get_mac_assoc_components($massoc, "massoc_root", "MIME Associations");
}

sub get_mac_components($$)
{
    my ($self, $massoc)=@_;

    my @mac_components = [ @{$self->get_mac_massoc_components($massoc)} ];

    foreach my $eassoc (values %{$massoc->{eassocs}})
    {
        my $eassoc_components=$self->get_mac_eassoc_components($eassoc);
        push @mac_components, [ @$eassoc_components ];
    }

    return \@mac_components;
}

sub component_to_dict($$)
{
    my ($component, $dict)=@_;

    if ($component->{appid})
    {
        CXPlist::add_key_with_string($dict, "Application ID", $component->{appid});
    }
    if ($component->{appname})
    {
        CXPlist::add_key_with_string($dict, "Application Name", $component->{appname});
    }
    if ($component->{command})
    {
        CXPlist::add_key_with_string($dict, "Command", $component->{command});
    }
    if ($component->{description})
    {
        CXPlist::add_key_with_string($dict, "Description", $component->{description});
    }
    if ($component->{ext})
    {
        CXPlist::add_key_with_string($dict, "Extension", $component->{ext});
    }
    if ($component->{mode})
    {
        CXPlist::add_key_with_string($dict, "Mode", $component->{mode});
    }
    if ($component->{verb})
    {
        CXPlist::add_key_with_string($dict, "Verb", $component->{verb});
    }
    if ($component->{verbname})
    {
        CXPlist::add_key_with_string($dict, "Verb Name", $component->{verbname});
    }
    if ($component->{_mac_icon})
    {
        CXPlist::add_key_with_string($dict, "Icon", $component->{_mac_icon});
        my $icon = $component->{_mac_icon};
        $icon =~ s!^\Q$ENV{WINEPREFIX}\E/!%WINEPREFIX%/! if defined($ENV{WINEPREFIX});
        $icon =~ s!^\Q$ENV{CX_ROOT}\E/!%CX_ROOT%/!;
        CXPlist::add_key_with_string($dict, "RobustIcon", $icon);
    }
    if ($component->{_mac_mimetype})
    {
        CXPlist::add_key_with_string($dict, "MIME Type", $component->{_mac_mimetype});
    }
}

sub get_folder($$$$)
{
    my ($self, $parent, $mac_path, $mac_key)=@_;

    if (exists $self->{folders}->{$mac_path})
    {
        return $self->{folders}->{$mac_path};
    }

    my $folder=CXPlist::get_value_by_name($parent, $mac_key);
    $self->{folders}->{$mac_path}=$folder;
    return $folder;
}


#####
#
# XML file creation and parsing
#
#####

sub init_xml($)
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
        cxlog("Creating Mac OS X association plist file\n");
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
    return 1;
}


#####
#
# MIME type creation and deletion
#
#####

# In this function we want to get a list of the *native XDG* MIME types
# and their associated extensions. We don't want to include any MIME type
# created by CrossOver in this list.
sub read_mime_db($)
{
    my ($self)=@_;
    return if (!$self->init_xml());
    return if ($self->{read_mime_db});
    $self->{read_mime_db}=1;

    my %mimetypes;
    my $parent=$self->{tags_root};
    my $path="";
    foreach my $component ("$self->{tag}/", "Extension Associations/")
    {
        $path.=$component;
        my $folder=$self->get_folder($parent, $path, $component);
        return if (!defined $folder);
        $parent=$folder;
    }

    my $key=find_tag($parent, "key");
    while (defined $key)
    {
        my $eassoc_dict=CXPlist::get_value_by_key($key);
        last if (!defined $eassoc_dict);
        $key=find_next_tag($eassoc_dict, "key");

        my $node=CXPlist::get_value_by_name($eassoc_dict, "MIME Type");
        next if (!defined $node);
        my $mimetype=get_cdata($node);
        $node=CXPlist::get_value_by_name($eassoc_dict, "Extension");
        next if (!defined $node);
        my $ext=get_cdata($node);

        $mimetypes{$mimetype}->{$ext}=1;
    }

    foreach my $mimetype (keys %mimetypes)
    {
        my @exts=keys %{$mimetypes{$mimetype}};
        $self->mdb_add_mime($mimetype, \@exts);
    }
}

sub create_mime($$$$$$)
{
    my ($self, $domain, $massoc, $mime, $mimetype, $extensions)=@_;
    CXAssoc::setup_from_best_eassoc($mime);
    return 1;
}

sub query_mime($$$$$)
{
    my ($self, $domain, $massoc, $mimetype, $extensions)=@_;
    return 0 if (!$self->init_xml());

    my $parent=$self->{tags_root};
    my $path="";
    foreach my $component ("$self->{tag}/", "MIME Associations/", $massoc->{id})
    {
        $path.=$component;
        my $folder=$self->get_folder($parent, $path, $component);
        return 0 if (!defined $folder);
        $parent=$folder;
    }

    return 1;
}

sub untag_mime($$$$)
{
    my ($self, $domain, $massoc, $mimetype)=@_;
    return 1;
}


#####
#
# Association desktop file helper functions
#
#####

sub create_association($$$$)
{
    my ($self, $massoc, $all_mimes, $extensions)=@_;
    return 0 if (!$self->init_xml());

    CXAssoc::setup_from_best_eassoc($massoc);
    CXAssoc::compute_verb_name($massoc);

    my $mac_components=$self->get_mac_components($massoc);
    foreach my $component_list (@$mac_components)
    {
        my $parent=$self->{tags_root};
        my $in_cache=1;
        foreach my $component (@$component_list)
        {
            my $folder;
            $folder=$self->{folders}->{$component->{_mac_path}} if ($in_cache);
            if (!defined $folder)
            {
                $in_cache=undef;
                $folder=CXPlist::get_value_by_name($parent, $component->{_mac_key});
            }
    
            if (!defined $folder)
            {
                cxlog("creating $component->{_mac_path}\n");
                $folder=CXPlist::add_key_with_new_tag($parent, $component->{_mac_key}, "dict");
                component_to_dict($component, $folder);
                $self->{folders}->{$component->{_mac_path}}=$folder;
            }
            # Directories don't need to be recreated. If they exist, that's
            # all we care about. Only recreate leaves.
            elsif (!$component->{is_dir})
            {
                cxlog("recreating $component->{_mac_path}\n");
    
                # Overwrite the old properties
                my $new_folder=create_element($parent->getOwnerDocument(), "dict");
                $parent->replaceChild($new_folder, $folder);
                component_to_dict($component, $new_folder);

                $folder=$new_folder;
                $self->{folders}->{$component->{_mac_path}}=$folder;
            }
            $parent=$folder;
        }
    }

    $self->{modified}=1;
    return 1;
}

sub query_association($$$$)
{
    my ($self, $massoc, $all_mimes, $state)=@_;
    return 0 if (!$self->init_xml());

    my $mac_components=$self->get_mac_components($massoc);
    foreach my $component_list (@$mac_components)
    {
        my $parent=$self->{tags_root};
        foreach my $component (@$component_list)
        {
            my $folder=$self->get_folder($parent, $component->{_mac_path},
                                      $component->{_mac_key});
            return $state if (!defined $folder);
            $parent=$folder;
        }
    }

    return "alternative";
}

sub delete_association($$)
{
    my ($self, $massoc)=@_;
    return 0 if (!$self->init_xml());

    # Get hold of the folder
    my $mac_components=$self->get_mac_components($massoc);
    LIST: foreach my $component_list (@$mac_components)
    {
        my $folder;
        my $parent=$self->{tags_root};
        foreach my $component (@$component_list)
        {
            $folder=$self->get_folder($parent, $component->{_mac_path},
                                      $component->{_mac_key});
            next LIST if (!defined $folder);
            $parent=$folder;
        }
    
        # Delete it
        my $mac_path=$component_list->[-1]->{_mac_path};
        cxlog("Deleting $mac_path\n");
        $parent=$folder->getParentNode();
        my $key=CXPlist::get_key_by_value($folder);
        remove_element($parent, $key);
        remove_element($parent, $folder);
        $self->{folders}->{$mac_path}=undef;
    
        # Always mark the parent folder for garbage collection
        $self->{garbage_collect}->{$component_list->[-2]->{_mac_path}}=1;
    }

    $self->{modified}=1;

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
        tag            => $cxoptions->{tag},
        mimealiases    => $cxoptions->{mimealiases},
        mimeignorelist => $cxoptions->{mimeignorelist},
        desktopdata    => $cxoptions->{desktopdata},
        xml_file       => "$cxoptions->{desktopdata}/cxassoc/cxassoc_macosx.plist",
        do_assoc       => 1
    };
    bless $self, $class;

    return ($self);
}

sub id($)
{
    return "CXAssocMacOSX/";
}

sub preinstall($$)
{
    my ($self, $massoc)=@_;
    return $self->collect_unix_extensions($massoc);
}

sub install($$)
{
    my ($self, $massoc)=@_;
    return $self->action($self, $massoc, "install");
}

sub query($$)
{
    my ($self, $massoc)=@_;
    return { alternative => $self->id() } if (!$massoc);
    return $self->action($self, $massoc, "query");
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
    my ($self, $massoc)=@_;
    return $self->action($self, $massoc, "uninstall");
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

# This garbage collection code is copied from CXMenu. It should be
# consolidated into shared code such that both the menu and assoc subsystems 
# can use it. Until then, I'm kludging it.

# When creating associations, intermediate folders are created implicitly. This
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
#   The folder does not contain any sub-folder or association and thus can be deleted
#
# * non-empty
#   The folder still contains associationss or sub-folders although none of them
#   belong to the current bottle. So we can remove the bottle's tag but we
#   must not delete the folder.
#
# * in-use
#   The folder contains at least one association or sub-folder belonging to the
#   current bottle. This means it must not be deleted and that the bottle's
#   tag must not be removed either.
#
# * alien
#   This folder does not belong to us at all. There is no tag to remove (by
#   definition) and we should not delete the folder.
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
    my $in_use=0;
    my $folder_name=CXXMLDOM::get_cdata($folder);
    if ($folder_name eq "MIME Associations" or $folder_name eq "Extension Associations")
    {
        # The associations dictionaries are in use if they have any contents.
        $in_use=1 if (find_tag($folder, "key"));
    }
    else
    {
        # The tag dictionary is only in use if it has one or more associations
        # dictionaries. Any other properties (i.e. Description) don't count.
        if (CXPlist::get_value_by_name($folder, "MIME Associations") or
            CXPlist::get_value_by_name($folder, "Extension Associations"))
        {
            $in_use=1;
        }
    }
    return ("in-use", $folder) if ($in_use);

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

sub garbage_collect($)
{
    my ($self)=@_;

    my $garbage_collect=$self->{garbage_collect};
    return if (!$garbage_collect or !%$garbage_collect);

    # If a folder is marked for garbage collection,
    # then all its parents should be too
    foreach my $path (sort { $b cmp $a } keys %$garbage_collect)
    {
        set_path_closure($garbage_collect, $path, 1);
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
        set_path_closure($status, $path, "in-use");
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
            set_path_closure($status, $path, "in-use");
        }
    }
}

sub finalize($)
{
    my ($self)=@_;
    return 0 if (!$self->{xml});

    $self->garbage_collect();

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
            CXUtils::garbage_collect_subdirs($self->{desktopdata}, "/cxassoc", 1);
        }
    }
    else
    {
        cxlog("XML file '$self->{xml_file}' not modified\n");
    }
    return 1;
}

return 1;
