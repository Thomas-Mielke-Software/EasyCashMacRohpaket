# (c) Copyright 2005-2014. CodeWeavers, Inc.
package CXAssocXDG;
use warnings;
use strict;

use CXLog;
use CXUtils;
use CXAssoc;
use base "CXAssoc";
use CXTinySAX;


#####
#
# MIME database helper functions
#
#####

{
    package Xml2MimeDB;
    use CXTinySAXBase;
    use base "CXTinySAXBase";
    use CXLog;
    use CXUtils;

    sub new($$)
    {
        my ($class, $xdg)=@_;
        my $self={ xdg => $xdg };
        bless $self, $class;
        return undef if (!$self->init());
        return $self;
    }

    sub encoding($$)
    {
        my ($self, $encoding)=@_;
        if ($encoding =~ /^utf-?8$/i)
        {
            delete $self->{encoding};
        }
        else
        {
            cxlog("re-encode from '$encoding' to 'utf8'\n");
            $self->{encoding}=$encoding;
        }
        return 1;
    }

    sub recode($$)
    {
        my ($self, $str)=@_;
        if (defined $self->{encoding})
        {
            require CXRecode;
            $str=CXRecode::from_to($str, $self->{encoding}, "utf8");
        }
        return $str;
    }

    sub start_element($$$)
    {
        my ($self, $element, $attributes)=@_;
        if ($element eq "mime-type" and $attributes->{type})
        {
            $self->{mimes}=[$self->recode($attributes->{type})];
        }
        elsif ($element eq "glob" and $attributes->{pattern})
        {
            my $extension=$self->recode($attributes->{pattern});
            $extension =~ s/^\*\.//;
            $extension =~ tr/A-Z/a-z/; # extensions are case-insensitive in XDG
            push @{$self->{extensions}}, $extension;

        }
        elsif ($element eq "alias" and $attributes->{type})
        {
            push @{$self->{mimes}}, $self->recode($attributes->{type});
        }

        return 1;
    }

    sub end_element($$)
    {
        my ($self, $element)=@_;
        if ($element eq "mime-type" and @{$self->{mimes}})
        {
            foreach my $mimetype (@{$self->{mimes}})
            {
                # XDG merges all the files together so take it all
                $self->{xdg}->mdb_add_mime($mimetype, $self->{extensions});
            }
            $self->{mimes}=[];
            $self->{extensions}=[];
        }
        return 1;
    }
}

# In this function we want to get a list of the *native XDG* MIME types
# and their associated extensions. We don't want to include any MIME type
# created by CrossOver in this list.
sub read_mime_db($)
{
    my ($self)=@_;
    return if ($self->{read_mime_db});
    $self->{read_mime_db}=1;

    my $handler=Xml2MimeDB->new($self);
    if ($ENV{CX_TINYSAXDEBUG})
    {
        # No need to load those unless we are going to use them
        eval "use CXTinySAXMultiplexer; use CXTinySAXLog;";
        $handler=CXTinySAXMultiplexer->new([CXTinySAXLog->new(), $handler]);
    }

    foreach my $dir (@{$self->{xdg_dirs}})
    {
        my $pkg_dir="$dir/mime/packages";
        next if (!-d $pkg_dir);
        my $dh;
        if (!opendir($dh, $pkg_dir))
        {
            cxlog("unable to open the '$pkg_dir' directory: $!\n");
            next;
        }
        foreach my $dentry (readdir $dh)
        {
            next if ($dentry =~ /^cxassoc-/); # Ignore CrossOver MIME types
            next if ($dentry !~ /\.xml$/);
            if (-f "$pkg_dir/$dentry")
            {
                my $start=CXLog::cxtime();
                CXTinySAX::parse_file($handler, "$pkg_dir/$dentry");
                cxlog("parsing took ", CXLog::cxtime()-$start, " seconds\n");
            }
        }
        closedir($dh);
    }
}


#####
#
# Reading and writing the CrossOver XML MIME file
#
#####

{
    package ReadCXMimes;
    use CXTinySAXBase;
    use base "CXTinySAXBase";
    use CXLog;
    use CXUtils;

    sub new($$)
    {
        my ($class, $xdg)=@_;
        my $self={
            xdg => $xdg,
            tag => ""
        };
        bless $self, $class;
        return undef if (!$self->init());
        return $self;
    }

    sub encoding($$)
    {
        my ($self, $encoding)=@_;
        if ($encoding =~ /^utf-?8$/i)
        {
            delete $self->{recode};
        }
        else
        {
            cxlog("re-encode from '$encoding' to 'utf8'\n");
            $self->{encoding}=$encoding;
        }
        return 1;
    }

    sub recode($$)
    {
        my ($self, $str)=@_;
        if ($self->{encoding})
        {
            require CXRecode;
            $str=CXRecode::from_to($str, $self->{encoding}, "utf8");
        }
        return $str;
    }

    sub start_element($$$)
    {
        my ($self, $element, $attributes)=@_;
        if ($element eq "mime-type" and $attributes->{type})
        {
            my $mimetype=$self->recode($attributes->{type});
            my $cxmime=$self->{xdg}->{cxmimes}->{$mimetype};
            if (defined $cxmime)
            {
                cxlog("'$mimetype' has already been found!\n");
            }
            else
            {
                $cxmime={ mimetype => $mimetype };
                $self->{xdg}->{cxmimes}->{$mimetype}=$cxmime;
            }
            $self->{cxmime}=$cxmime;
        }
        elsif (!$self->{cxmime})
        {
            # Without a current cxmime object there is nothing to do
        }
        elsif ($element eq "glob" and $attributes->{pattern})
        {
            my $extension=$self->recode($attributes->{pattern});
            $extension =~ s/^\*\.//;
            $extension =~ tr/A-Z/a-z/; # extensions are case-insensitive in XDG
            $self->{cxmime}->{extensions}->{$extension}=1;

        }
        elsif ($element eq "comment")
        {
            $self->{tag}="comment";
            $self->{lang}=$self->recode($attributes->{"xml:lang"} || "");
        }
        elsif ($element eq "alias" and $attributes->{type})
        {
            cxlog("unexpected '$attributes->{type}' alias found for '$self->{cxmime}->{mimetype}'\n");
        }

        return 1;
    }

    sub end_element($$)
    {
        my ($self, $element)=@_;
        delete $self->{cxmime} if ($element eq "mime-type");
        $self->{tag}="";
        return 1;
    }

    sub cdata($$$)
    {
        my ($self, $element, $cdata)=@_;
        if ($self->{tag} eq "comment")
        {
            $self->{cxmime}->{comments}->{$self->{lang}}=$cdata;
        }
        return 1;
    }

    sub comment($$)
    {
        my ($self, $comment)=@_;
        if ($comment =~ s/^X-Created-By\s*=\s*//)
        {
            map { $self->{cxmime}->{apps}->{$_}=1 } split /;+/, $comment;
        }
        return 1;
    }
}

sub read_cxmimes($)
{
    my ($self)=@_;
    return if (exists $self->{cxmimes});

    my $handler=ReadCXMimes->new($self);
    if ($ENV{CX_TINYSAXDEBUG})
    {
        # No need to load those unless we are going to use them
        eval "use CXTinySAXMultiplexer; use CXTinySAXLog;";
        $handler=CXTinySAXMultiplexer->new([CXTinySAXLog->new(), $handler]);
    }

    my $filename="$self->{xdg_dir}/mime/packages/cxassoc-$self->{tag}.xml";
    my $start=CXLog::cxtime();
    CXTinySAX::parse_file($handler, $filename);
    cxlog("parsing took ", CXLog::cxtime()-$start, " seconds\n");
}

sub save_cxmimes($)
{
    my ($self)=@_;
    return 1 if (!$self->{modified_mime} or !exists $self->{cxmimes});

    my $filename="$self->{xdg_dir}/mime/packages/cxassoc-$self->{tag}.xml";
    if (!%{$self->{cxmimes}})
    {
        if (-f $filename)
        {
            cxlog("Deleting '$filename'\n");
            if (!unlink $filename)
            {
                cxwarn("unable to delete '$filename': $!\n");
                return 0;
            }
        }
        return 1;
    }

    my $dir=cxdirname($filename);
    if (!cxmkpath($dir))
    {
        cxerr("unable to create the '$dir' directory: $@\n");
        return 0;
    }

    my $fh;
    if (!open($fh, ">", $filename))
    {
        cxerr("unable to open '$filename' for writing: $!\n");
        return 0;
    }

    cxlog("Saving '$filename'\n");
    print $fh "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    print $fh "<mime-info xmlns=\"http://www.freedesktop.org/standards/shared-mime-info\">\n";
    foreach my $mimetype (sort keys %{$self->{cxmimes}})
    {
        my $cxmime=$self->{cxmimes}->{$mimetype};
        print $fh "  <mime-type type=\"",
                  CXTinySAX::mangle_attribute($mimetype), "\">\n";
        print $fh "    <!-- X-Created-By=",
                  CXTinySAX::mangle_cdata(join(";", keys %{$cxmime->{apps}})),
                  " -->\n";
        if (defined $cxmime->{icon})
        {
            print $fh "    <generic-icon name=\"$cxmime->{icon}\"/>\n";
        }
        foreach my $lang (sort keys %{$cxmime->{comments}})
        {
            my $attribute="";
            if ($lang ne "")
            {
                $attribute=" xml:lang=\"" .
                      CXTinySAX::mangle_attribute($lang) . "\"";
            }
            print $fh "    <comment$attribute>",
                      CXTinySAX::mangle_cdata($cxmime->{comments}->{$lang}),
                      "</comment>\n";
        }
        foreach my $extension (sort keys %{$cxmime->{extensions}})
        {
            print $fh "    <glob pattern=\"*.",
                      CXTinySAX::mangle_cdata($extension), "\"/>\n";
        }
        print $fh "  </mime-type>\n";
    }
    print $fh "</mime-info>\n";
    close($fh);
    return 1;
}


#####
#
# MIME icon creation and deletion
#
#####


sub create_icon($$$)
{
    # Notes:
    # - XDG used to provide no way to specify an icon for a given MIME type
    #   in its XML files.
    # - Now it's possible to specify an icon using either the <generic-icon>
    #   or the <icon> tags, but this breaks older GNOME versions (they use a
    #   validating XML parser). So it's best to avoid them.
    # - However GNOME will automatically use a file called:
    #   <root>/icons/hicolor/48x48/mimetypes/gnome-mime-<mimetype>.xpm
    # - Then we need to touch the hicolor directory to get GNOME to notice the
    #   new icons (see in finalize()).
    # - When KDE started using XDG MIME types, it looked for an icon by the
    #   same name except for the 'gnome-mime-' prefix.
    # - Since the icon name is fixed we cannot use it to identify our icons
    #   or isolate the bottles icons from each other. So we create them as
    #   symbolic links pointing to a file which name contains the bottle tag.
    #   Of course, that second file turns out to be a symbolic link to the
    #   real icon.
    # - All XDG implementations seem to support XPM icons.
    # - GNOME will also use gnome-mime-<mimetype>.xpm files placed in
    #   <root>/pixmaps but only for system-wide associations.
    my ($self, $mime, $mimetype)=@_;
    $self->delete_icon($mimetype);

    my $ext=$mime->{icon} =~ /\.xpm$/i ? ".xpm" : ".png";
    my $link="$self->{desktopdata}/cxassoc/tagged_icons/$self->{tag}." .
             mangle_string($mimetype) . $ext;
    cxlog("Creating '$link'\n");
    my $dir=cxdirname($link);
    if (!cxmkpath($dir))
    {
        cxlog("unable to create the '$dir' directory: $@\n");
    }

    if (!$self->{ro_desktopdata} or !-l $link)
    {
        my $ref_icon=$mime->{icon};
        $ref_icon =~ s!^\Q$ENV{WINEPREFIX}/\E!../../../! if (defined $ENV{WINEPREFIX});
        if (!symlink $ref_icon, $link)
        {
            cxlog("unable to symlink '$link' to '$ref_icon': $!\n");
        }
    }

    my $icon_dir="$self->{xdg_dir}/icons/hicolor/48x48/mimetypes";
    if (!cxmkpath($icon_dir))
    {
        cxlog("unable to create the '$icon_dir' directory: $@\n");
    }
    my $xdg_link="$icon_dir/$self->{tag}_". mangle_string($mimetype) . $ext;
    cxlog("Creating '$xdg_link'\n");
    if (!symlink $link, $xdg_link)
    {
        cxlog("unable to symlink '$xdg_link' to '$link': $!\n");
    }
}

sub delete_icon($$)
{
    my ($self, $mimetype)=@_;

    for my $ext (".xpm", ".png")
    {
        for my $rawdir (@{$self->{xdg_dirs}})
        {
            my $dir="$self->{destdir}$rawdir";
            next if (!-d $dir);
            if (!-w _)
            {
                cxlog("delete_icon: skipping read-only '$dir' directory\n");
                next;
            }
            my $icon_dir="$dir/icons/hicolor/48x48/mimetypes";
            my $icon=$mimetype;
            $icon =~ s!/!-!g;
            for my $prefix ("", "gnome-mime-")
            {
                my $xdg_link="$icon_dir/$prefix$icon$ext";
                if (-l $xdg_link and readlink($xdg_link) =~ m!/$self->{tag}\.!)
                {
                    cxlog("Deleting '$xdg_link'\n");
                    if (!unlink $xdg_link)
                    {
                        cxlog("unable to delete '$xdg_link': $!\n");
                    }
                    $self->{collect_icon_dir}->{$dir}=1;
                }
            }
        }

        my $link="$self->{desktopdata}/cxassoc/tagged_icons/$self->{tag}." .
                 mangle_string($mimetype) . $ext;
        if (!$self->{ro_desktopdata} and -l $link)
        {
            cxlog("Deleting '$link'\n");
            if (!unlink $link)
            {
                cxlog("unable to delete '$link': $!\n");
            }
        }
    }
}

sub get_icon_files($$)
{
    my ($self, $mimetype)=@_;

    my @files;
    my $icon=$mimetype;
    $icon =~ s!/!-!g;
    for my $ext (".xpm", ".png")
    {
        for my $rawdir (@{$self->{xdg_dirs}})
        {
            my $icon_dir="$self->{destdir}$rawdir/icons/hicolor/48x48/mimetypes";
            for my $prefix ("", "gnome-mime-")
            {
                my $xdg_link="$icon_dir/$prefix$icon$ext";
                if (-l $xdg_link and readlink($xdg_link) =~ m!/$self->{tag}\.!)
                {
                    push @files, $xdg_link;
                }
            }
        }
        my $link="$self->{desktopdata}/cxassoc/tagged_icons/$self->{tag}." .
                 mangle_string($mimetype) . $ext;
        push @files, $link if (-l $link);
    }
    return \@files;
}

sub removeall_icon($$)
{
    my ($self, $pattern)=@_;

    my $pat=$pattern;
    $pat="$pat.*" if ($pat !~ s/\$$//);
    for my $rawdir (@{$self->{xdg_dirs}})
    {
        my $dir="$self->{destdir}$rawdir";
        next if (!-d $dir);
        if (!-w _)
        {
            cxlog("removeall_icon: skipping read-only '$dir' directory\n");
            next;
        }
        my $icon_dir="$dir/icons/hicolor/48x48/mimetypes";
        if (opendir(my $dh, $icon_dir))
        {
            foreach my $dentry (readdir $dh)
            {
                next if ($dentry =~ /^\.\.?$/);
                $dentry="$icon_dir/$dentry";
                if (-l $dentry and readlink($dentry) =~ m!/$pat\..*\.(?:png|xpm)$!)
                {
                    cxlog("Deleting '$dentry'\n");
                    if (!unlink $dentry)
                    {
                        cxerr("unable to delete '$dentry': $!\n");
                    }
                    $self->{collect_icon_dir}->{$dir}=1;
                }
            }
            closedir($dh);
        }
        elsif (-d $icon_dir)
        {
            cxlog("unable to open the '$icon_dir' directory: $!\n");
        }
        # Linux distributions ship empty icon directories so don't garbage
        # collect them.
    }

    if (!$self->{ro_desktopdata})
    {
        if ($self->{tag} and $self->{tag} =~ /^$pattern/)
        {
            my $dir="$self->{desktopdata}/cxassoc/tagged_icons";
            if (-d $dir)
            {
                cxlog("Deleting the '$dir' directory\n");
                require File::Path;
                if (!File::Path::rmtree($dir))
                {
                    cxerr("unable to delete the '$dir' directory: $!\n");
                }
            }
            CXUtils::garbage_collect_subdirs($self->{desktopdata}, "/cxassoc", 1);
        }
        else
        {
            require CXBottle;
            CXBottle::removeall_desktopdata_dirs($pattern, "/cxassoc/tagged_icons");
        }
    }
}


#####
#
# MIME type creation and deletion
#
#####

sub create_mime($$$$$$)
{
    my ($self, $domain, $massoc, $mime, $mimetype, $extensions)=@_;
    $self->read_cxmimes();

    my $cxmime=$self->{cxmimes}->{$mimetype} || {};
    if (!$cxmime->{created})
    {
        cxlog("Creating '$mimetype'\n");
        # Recreate the MIME type from scratch...
        delete $cxmime->{icon};
        delete $cxmime->{comments};
        delete $cxmime->{extensions};

        $cxmime->{mimetype}=$mimetype;
        CXAssoc::setup_from_best_eassoc($mime);
        $cxmime->{icon}="$self->{tag}_". mangle_string($mimetype);
        my $description=$mime->{description} || $mimetype;
        $description.=" (" . $self->id() . ")" if ($ENV{CX_TAGALL});
        $cxmime->{comments}->{""}=$description;
        if ($mime->{localize})
        {
            my $oldlang=CXUtils::cxgetlang();
            my $oldencoding=CXUtils::cxsetencoding("UTF-8");
            foreach my $locale (CXUtils::get_supported_locales())
            {
                CXUtils::cxsetlang($locale);
                my $description=cxgettext($mime->{description});
                if ($description ne $mime->{description})
                {
                    $description.=" (" . $self->id() . ")" if ($ENV{CX_TAGALL});
                    $cxmime->{comments}->{$locale}=$description;
                }
            }
            CXUtils::cxsetlang($oldlang);
            CXUtils::cxsetencoding($oldencoding);
        }
        map { $cxmime->{extensions}->{$_}=1 } @$extensions;

        $self->{cxmimes}->{$mimetype}=$cxmime;
        $cxmime->{created}=1;

        $self->create_icon($mime, $mimetype);
    }
    else
    {
        cxlog("Tagging  '$mimetype'\n");
    }
    $cxmime->{apps}->{$massoc->{id}}=1;

    $self->{modified_mime}=1;
    return 1;
}

sub query_mime($$$$$)
{
    my ($self, $domain, $massoc, $mimetype, $extensions)=@_;
    $self->read_cxmimes();

    my $cxmime=$self->{cxmimes}->{$mimetype};
    return 0 if (!$cxmime->{apps}->{$massoc->{id}});
    foreach my $ext (@$extensions)
    {
        return 0 if (!$cxmime->{extensions}->{$ext});
    }

    return 1;
}

sub get_mime_files($$$$$)
{
    my ($self, $domain, $massoc, $mimetype, $extensions)=@_;

    my @files;
    for my $rawdir (@{$self->{xdg_dirs}})
    {
        my $filename="$self->{destdir}$rawdir/mime/packages/cxassoc-$self->{tag}.xml";
        push @files, $filename if (-f $filename);
    }
    push @files, @{$self->get_icon_files($mimetype)};
    return \@files;
}

sub untag_mime($$$$)
{
    my ($self, $domain, $massoc, $mimetype)=@_;
    $self->read_cxmimes();

    my $in_use;
    cxlog("Untagging '$mimetype'\n");
    my $cxmime=$self->{cxmimes}->{$mimetype};
    if (defined $cxmime)
    {
        delete $cxmime->{apps}->{$massoc->{id}};
        if (!%{$cxmime->{apps}})
        {
            # No one is using this MIME type anymore
            delete $self->{cxmimes}->{$mimetype};
        }
        else
        {
            $in_use=1;
        }
        $self->{modified_mime}=1;
    }
    $self->delete_icon($mimetype) if (!$in_use);

    return 1;
}


#####
#
# Association desktop file helper functions
#
#####

sub create_association($$$$)
{
    my ($self, $massoc, $adata, $extensions)=@_;

    # If KDEXDG is in use, then we must also take into account its MIME types
    if ($massoc->{_kdexdg_all_mimes})
    {
        foreach my $mimetype (keys %{$massoc->{_kdexdg_all_mimes}})
        {
            if (!$adata->{all_mimes}->{$mimetype} and
                !$self->ignore_mime_alias($massoc, $adata, $mimetype))
            {
                $adata->{all_mimes}->{$mimetype}=1;
            }
        }
        cxlog("  after kdexdg-ca: ", join(" ", sort keys %{$adata->{all_mimes}}), "\n");
    }

    my $filename="$self->{xdg_dir}/applications";
    if (!cxmkpath($filename))
    {
        cxerr("unable to create the '$filename' directory: $@\n");
        return 0;
    }

    require CXRWConfig;
    my $desktop=CXRWConfig->new(undef, "xdg", "");
    $filename.="/cxassoc-$self->{tag}:$massoc->{id}.desktop";
    cxlog("Creating '$filename'\n");
    $desktop->set_filename($filename);
    my $section=$desktop->append_section("Desktop Entry");
    $section->set("Encoding", "UTF-8");
    $section->set("Type", "Application");
    $section->set("X-Created-By", $self->{tag});
    $section->set("NoDisplay", "true");

    CXAssoc::setup_from_best_eassoc($massoc);
    $section->set("Icon", $massoc->{icon});

    my $name=$massoc->{appname};
    if ($massoc->{verb})
    {
        CXAssoc::compute_verb_name($massoc);
        if ($massoc->{verbname})
        {
            # Notes:
            # - With the verb name coming last, its placement is wrong for
            #   defining a keyboard shortcut.
            # - KDE creates a keyboard shortcut when it finds the VerbName's
            #   ampersand, but GNOME just leaves it in the string. This means
            #   if the string has 'real' ampersands, the first one will be
            #   turned into a keyboard shortcut by KDE while it will look ok
            #   in GNOME. But if we double it so it looks ok in KDE, then it
            #   is in GNOME it will look wrong.
            $name.=" (" . CXAssoc::remove_accelerators($massoc->{verbname}) . ")";
        }
    }
    my $creator;
    if ($ENV{CX_TAGALL})
    {
        $creator=" (" . ($massoc->{_kdexdg_id} || "") . $self->id() . ")";
        $name.=$creator;
    }
    $section->set("Name", $name);
    if ($massoc->{localize} or $massoc->{stdverbname})
    {
        my $oldlang=CXUtils::cxgetlang();
        my $oldencoding=CXUtils::cxsetencoding("UTF-8");
        my $std_verb_names=CXAssoc::std_verb_names();
        foreach my $locale (CXUtils::get_supported_locales())
        {
            CXUtils::cxsetlang($locale);
            my $appname=$massoc->{appname};
            $appname=cxgettext($appname) if ($massoc->{localize});
            my $verbname=$std_verb_names->{$massoc->{verb}};
            $verbname=cxgettext($verbname) if ($massoc->{localize} or $massoc->{stdverbname});
            if ($appname ne $massoc->{appname} or $verbname ne $std_verb_names->{$massoc->{verb}})
            {
                my $name="$appname (" . CXAssoc::remove_accelerators($verbname) . ")";
                $name.=$creator if ($creator);
                $section->set("Name[$locale]", $name);
            }
        }
        CXUtils::cxsetlang($oldlang);
        CXUtils::cxsetencoding($oldencoding);
    }
    $section->set("GenericName", $massoc->{genericname}) if ($massoc->{genericname});
    if ($massoc->{genericname} and $massoc->{localize})
    {
        my $oldlang=CXUtils::cxgetlang();
        my $oldencoding=CXUtils::cxsetencoding("UTF-8");
        foreach my $locale (CXUtils::get_supported_locales())
        {
            CXUtils::cxsetlang($locale);
            my $genericname=cxgettext($massoc->{genericname});
            if ($genericname ne $massoc->{genericname})
            {
                $section->set("GenericName[$locale]", $genericname);
            }
        }
        CXUtils::cxsetlang($oldlang);
        CXUtils::cxsetencoding($oldencoding);
    }

    # The desktop file format specifies that percents must be doubled.
    my $exec=$massoc->{command};
    $exec =~ s/%/%%/g;
    $section->set("Exec", "$exec \%u");
    $section->set("Terminal", "false");
    $section->set("MimeType", join(";", (sort keys %{$adata->{all_mimes}}), ""));

    # KDE (up to 4.2.2) ignores the defaults.list file,
    # forcing us to use the InitialPreference field instead.
    my $preference=($massoc->{mode} eq "default") ? 10 : 1;
    $section->set("InitialPreference", $preference);

    if (!$desktop->save())
    {
        cxerr("unable to save '$filename': $!\n");
        return 0;
    }
    $self->{modified_desktop}=1;
    return 1;
}

sub query_association($$$$)
{
    my ($self, $massoc, $adata, $state)=@_;

    # If KDEXDG is in use, then we must also take into account its MIME types
    if ($massoc->{_kdexdg_all_mimes})
    {
        foreach my $mimetype (keys %{$massoc->{_kdexdg_all_mimes}})
        {
            if (!$adata->{all_mimes}->{$mimetype} and
                !$self->ignore_mime_alias($massoc, $adata, $mimetype))
            {
                $adata->{all_mimes}->{$mimetype}=1;
            }
        }
        cxlog("  after kdexdg-qa: ", join(" ", sort keys %{$adata->{all_mimes}}), "\n");
    }

    my $found;
    for my $rawdir (@{$self->{xdg_dirs}})
    {
        my $dir="$self->{destdir}$rawdir";
        if (-f "$dir/applications/cxassoc-$self->{tag}:$massoc->{id}.desktop")
        {
            $found=1;
            last;
        }
    }
    return $state if (!$found);

    require CXRWConfig;
    my $filename="$self->{xdg_dir}/applications/cxassoc-$self->{tag}:$massoc->{id}.desktop";
    my $desktop=CXRWConfig->new($filename, "xdg", "");
    cxlog("Checking '$filename'\n");

    my $section=$desktop->get_section("Desktop Entry");
    return $state if (!$section);

    my $str=$section->get("MimeType", "");
    my @mimes=split /;+/, $str;
    return $state if (CXAssoc::compare_sets(\@mimes, $adata->{all_mimes}));

    # Dedouble percents before we check the command
    $str=$section->get("Exec", "");
    $str =~ s/%%/%/g;
    return $state if ($str !~ /\Q$massoc->{cmdbase}\E(?:[^:]|$)/);

    return "alternative";
}

sub get_association_files($$$$)
{
    my ($self, $massoc, $adata, $state)=@_;

    my @files;
    for my $rawdir (@{$self->{xdg_dirs}})
    {
        my $filename="$self->{destdir}$rawdir/applications/cxassoc-$self->{tag}:$massoc->{id}.desktop";
        push @files, $filename if (-f $filename);
    }
    return \@files;
}

sub delete_association($$$)
{
    my ($self, $massoc)=@_;

    $self->{modified_desktop}=1;
    my $success=1;
    for my $rawdir (@{$self->{xdg_dirs}})
    {
        my $dir="$self->{destdir}$rawdir";
        next if (!-d $dir);
        if (!-w _)
        {
            cxlog("delete_asociation: skipping read-only '$dir' directory\n");
            next;
        }
        my $filename="$dir/applications/cxassoc-$self->{tag}:$massoc->{id}.desktop";
        require CXRWConfig;
        CXRWConfig::uncache_file($filename);
        if (-f $filename)
        {
            cxlog("Deleting '$filename'\n");
            if (!unlink $filename)
            {
                cxerr("unable to delete '$filename': $!\n");
                $success=0;
            }
        }
    }
    return $success;
}


#####
#
# defaults.list file helper functions
#
#####

sub read_defaults($$)
{
    my ($self)=@_;
    return if (exists $self->{defaults});

    my $filename="$self->{xdg_dir}/applications/defaults.list";
    require CXRWConfig;
    $self->{def_file}=CXRWConfig->new($filename, "xdg", "");
    $self->{def_section}=$self->{def_file}->append_section("Default Applications");
    foreach my $mimetype (@{$self->{def_section}->get_field_list()})
    {
        my $value=$self->{def_section}->get($mimetype);
        my $count=1;
        foreach my $app (split /;+/, $value)
        {
            $self->{def_apps}->{$app}->{$mimetype}=$count++;
        }
    }
}

sub create_default($$$)
{
    my ($self, $massoc, $adata)=@_;
    $self->read_defaults();

    # If KDEXDG is in use, then we must also take into account its MIME types
    if ($massoc->{_kdexdg_default_mimes})
    {
        foreach my $mimetype (keys %{$massoc->{_kdexdg_default_mimes}})
        {
            if (!$adata->{default_mimes}->{$mimetype} and
                !$self->ignore_mime_alias($massoc, $adata, $mimetype))
            {
                $adata->{default_mimes}->{$mimetype}=1;
            }
        }
        cxlog("  after kdexdg-cd: ", join(" ", sort keys %{$adata->{default_mimes}}), "\n");
    }

    my $desktop="cxassoc-$self->{tag}:$massoc->{id}.desktop";
    foreach my $mimetype (keys %{$self->{def_apps}->{$desktop}})
    {
        if (!$adata->{default_mimes}->{$mimetype})
        {
            $self->{def_section}->remove($mimetype);
            delete $self->{def_apps}->{$desktop}->{$mimetype};
        }
    }
    if (!%{$self->{def_apps}->{$desktop}})
    {
        delete $self->{def_apps}->{$desktop}; # for finalize()
    }

    foreach my $mimetype (keys %{$adata->{default_mimes}})
    {
        if (($self->{def_apps}->{$desktop}->{$mimetype} || "") ne "1")
        {
            my @list=($desktop);
            my $str=$self->{def_section}->get($mimetype, "");
            my $count=2;
            foreach my $item (split /;+/, $str)
            {
                if ($item ne $desktop)
                {
                    push @list, $item;
                    $self->{def_apps}->{$item}->{$mimetype}=$count++;
                }
            }
            $self->{def_apps}->{$desktop}->{$mimetype}=1;
            $self->{def_section}->set($mimetype, join(";", @list));
        }
    }

    return 1;
}

sub query_default($$$$)
{
    my ($self, $massoc, $adata, $state)=@_;
    return "alternative" if (!%{$adata->{default_mimes}});
    $self->read_defaults();

    # If KDEXDG is in use, then we must also take into account its MIME types
    if ($massoc->{_kdexdg_default_mimes})
    {
        foreach my $mimetype (keys %{$massoc->{_kdexdg_default_mimes}})
        {
            if (!$adata->{default_mimes}->{$mimetype} and
                !$self->ignore_mime_alias($massoc, $adata, $mimetype))
            {
                $adata->{default_mimes}->{$mimetype}=1;
            }
        }
        cxlog("  after kdexdg-qd: ", join(" ", sort keys %{$adata->{default_mimes}}), "\n");
    }

    my $desktop="cxassoc-$self->{tag}:$massoc->{id}.desktop";
    my $default_mimes=$self->{def_apps}->{$desktop};
    foreach my $mimetype (keys %$default_mimes)
    {
        if (!$adata->{default_mimes}->{$mimetype})
        {
            cxlog("extra MIME type: $mimetype\n");
            return "alternative";
        }
    }
    foreach my $mimetype (keys %{$adata->{default_mimes}})
    {
        if (($default_mimes->{$mimetype} || "") ne "1")
        {
            cxlog("$desktop missing or not first in list for $mimetype\n");
            return "alternative";
        }
    }

    return "default";
}

sub get_default_files($$$$)
{
    my ($self, $massoc, $adata, $state)=@_;
    # The defaults.list file is not specific to this bottle and thus
    # must not be packaged with it.
    return [];
}

sub delete_default($$)
{
    my ($self, $massoc)=@_;
    $self->read_defaults();

    my $desktop="cxassoc-$self->{tag}:$massoc->{id}.desktop";
    foreach my $mimetype (keys %{$self->{def_apps}->{$desktop}})
    {
        my $str=$self->{def_section}->get($mimetype, "");
        if ($str eq $desktop)
        {
            $self->{def_section}->remove($mimetype);
        }
        else
        {
            my @list=grep !/^$desktop$/, split /;+/, $str;
            $self->{def_section}->set($mimetype, join(";", @list));
        }
    }
    delete $self->{def_apps}->{$desktop};
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
    return () if (!$gui_info->{xdg_mime_on} or
                  !$gui_info->{xdg_preferred_data});

    my $self={
        tag            => $cxoptions->{tag},
        winexts        => $cxoptions->{winexts},
        winmimes       => $cxoptions->{winmimes},
        mimealiases    => $cxoptions->{mimealiases},
        mimeignorelist => $cxoptions->{mimeignorelist},
        massocs        => $cxoptions->{massocs},
        destdir        => $cxoptions->{destdir},
        desktopdata    => $cxoptions->{desktopdata},
        ro_desktopdata => $cxoptions->{ro_desktopdata},
        id             => $gui_info->{xdg_preferred_data},
        xdg_dir        => "$cxoptions->{destdir}$gui_info->{xdg_preferred_data}",
        xdg_global_dir => "$cxoptions->{destdir}$gui_info->{xdg_global_data}",
        do_assoc       => 1,
        do_default     => 1,
        kde_mime_path  => $gui_info->{kde_mime_path},
    };
    $self->{xdg_dirs}=[grep {$_ ne ""} split /:+/, $gui_info->{xdg_data_dirs}];
    if ($gui_info->{preferred_scope} eq "private")
    {
        # xdg_data_dirs only contains directories for the managed scope so
        # xdg_preferred_data must be added to the list manually.
        unshift @{$self->{xdg_dirs}}, $gui_info->{xdg_preferred_data};
    }
    bless $self, $class;

    return ($self);
}

sub id($)
{
    my ($self)=@_;
    my $id="CXAssocXDG/$self->{id}";
    $id =~ s%/+%/%g;
    return $id;
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

    if (!$massoc)
    {
        my $id=$self->id();
        return {default     => $id,
                alternative => $id,
                mime        => $id,
                partial     => $id};
    }
    return $self->action($self, $massoc, "query");
}

sub get_files($$)
{
    my ($self, $massoc)=@_;
    return $self->action($self, $massoc, "getfiles");
}

sub uninstall($$)
{
    my ($self, $massoc)=@_;
    return $self->action($self, $massoc, "uninstall");
}

sub removeall_kde_mimes($$)
{
    my ($self, $domain, $pattern)=@_;
    # Until CrossOver 14.0.3 CXAssocXDG usually created KDE MIME types through
    # CXassocKDEXDG. It no longer does but still has to clean those up.

    require CXConfig;
    my @dirs=split /:+/, $self->{kde_mime_path};
    while (@dirs)
    {
        my $dir=$self->{destdir} . shift @dirs;
        next if (!-w $dir);

        my $rmdir=1;
        if (opendir(my $dh, $dir))
        {
            foreach my $dentry (readdir $dh)
            {
                next if ($dentry =~ /^\.\.?$/);
                my $path="$dir/$dentry";
                if (-d $path)
                {
                    push @dirs, $path;
                    next;
                }
                next if ($dentry !~ /\.desktop$/);

                my $cxmime=CXConfig->new($path);
                my $created_by=$cxmime->get("Desktop Entry", "X-Created-By", "");
                cxlog("  created_by=[$created_by]\n");
                next if ($created_by ne "CrossOver");

                cxlog("Deleting '$path'\n");
                if (!unlink $path)
                {
                    cxerr("unable to delete '$path': $!\n");
                }
                $rmdir=1;
            }
            closedir($dh);

            # Try to delete the parent directory to limit accumulation of cruft
            rmdir $dir if ($rmdir);
        }
    }
}

sub removeall($$)
{
    my ($self, $pattern)=@_;
    my $pat;

    # Scan the MIME database for our MIME types
    if ($pattern eq "legacy")
    {
        $pat=CXUtils::get_product_id() . "-app-\\d{5}";
    }
    else
    {
        $pat="cxassoc-$pattern";
        $pat="$pat.*" if ($pat !~ s/\$$//);
        $self->removeall_kde_mimes();
    }
    foreach my $rawdir (@{$self->{xdg_dirs}})
    {
        my $dir="$self->{destdir}$rawdir";
        next if (!-d $dir);
        if (!-w _)
        {
            cxlog("removeall1: skipping read-only '$dir' directory\n");
            next;
        }
        if (CXUtils::delete_files("$dir/mime/packages", "^$pat\\.xml\$") > 0)
        {
            $self->{modified_mime}=1;
        }
    }
    $self->removeall_icon($pattern);

    # Scan the application database for our associations
    # Scan the MIME database for our MIME types
    if ($pattern eq "legacy")
    {
        $pat=CXUtils::get_product_id() . "-app-\\d{5}";
    }
    else
    {
        $pat=$pattern;
        $pat="$pat\[^:]*" if ($pat !~ s/\$$//);
        $pat="cxassoc-$pat:.*";
    }
    foreach my $rawdir (@{$self->{xdg_dirs}})
    {
        my $dir="$self->{destdir}$rawdir";
        next if (!-d $dir);
        if (!-w _)
        {
            cxlog("removeall2: skipping read-only '$dir' directory\n");
            next;
        }
        if (CXUtils::delete_files("$dir/applications", "^$pat\\.desktop\$") > 0)
        {
            $self->{modified_desktop}=1;
        }
    }

    # Scan the defaults database for our associations
    $self->read_defaults();
    foreach my $desktop (keys %{$self->{def_apps}})
    {
        if ($desktop =~ /^$pat\.desktop$/)
        {
            foreach my $mimetype (keys %{$self->{def_apps}->{$desktop}})
            {
                my $str=$self->{def_section}->get($mimetype, "");
                if ($str eq $desktop)
                {
                    $self->{def_section}->remove($mimetype);
                }
                else
                {
                    my @list=grep !/^$desktop$/, split /;+/, $str;
                    $self->{def_section}->set($mimetype, join(";", @list));
                }
            }
            delete $self->{def_apps}->{$desktop};
        }
    }

    return 1;
}

sub finalize($)
{
    my ($self)=@_;
    my $rc=1;

    if ($self->{def_file})
    {
        my $filename=$self->{def_file}->get_filename();
        if (!%{$self->{def_apps}} and
            $self->{def_file}->get_section_names() == 1)
        {
            if (-f $filename)
            {
                cxlog("Deleting '$filename'\n");
                if (!unlink $filename)
                {
                    cxwarn("unable to delete '$filename': $!\n");
                    $rc=0;
                }
            }
        }
        elsif (!$self->{def_file}->save())
        {
            cxerr("unable to save '$filename': $!\n");
        }
    }

    if ($self->{modified_mime})
    {
        # {modified_mime} must be set whenever the MIME type xml file is
        # created, modified or deleted. We must then run update-mime-database.
        $rc=0 if (!$self->save_cxmimes());
        if (!$self->{destdir})
        {
            cxsystem("update-mime-database " .
                     shquote_string("$self->{xdg_dir}/mime") . " >/dev/null");
        }
    }
    for my $dir (keys %{$self->{collect_icon_dir}})
    {
        if (-d "$dir/icons/hicolor")
        {
            CXUtils::garbage_collect_subdirs($dir, "/icons/hicolor/48x48/mimetypes", 1);
        }
    }
    # Get XDG to notice our new icons
    my $now=time();
    utime $now, $now, "$self->{xdg_dir}/icons/hicolor";

    if (!$self->{ro_desktopdata} and defined $self->{desktopdata})
    {
        CXUtils::garbage_collect_subdirs($self->{desktopdata},
                                         "/cxassoc/tagged_icons", 1);
    }

    if ($self->{modified_desktop} and !$self->{destdir})
    {
        # {modified_desktop} must be set whenever an association desktop
        # file is created, modified or deleted. We must then run
        # update-desktop-database to regenerate mimeinfo.cache.
        # Note: On SUSE 9.3 update-desktop-database is not in the
        #       PATH when invoked from the RPM postinstall script.
        my $path="$ENV{PATH}:/opt/gnome/bin";
        my $updater=CXUtils::cxwhich($path, "update-desktop-database");
        if (defined $updater)
        {
            my @cmd=($updater, "-q");
            if ($self->{xdg_dir} ne $self->{xdg_global_dir})
            {
                # By default update-desktop-database tries to modify the
                # global files. So in this case we must specify the path
                # explicitly.
                push @cmd, "$self->{xdg_dir}/applications";
            }
            cxsystem(@cmd);
        }
        else
        {
            cxwarn("unable to find 'update-desktop-database' in '$path'\n");
        }
    }

    return $rc;
}

return 1;
