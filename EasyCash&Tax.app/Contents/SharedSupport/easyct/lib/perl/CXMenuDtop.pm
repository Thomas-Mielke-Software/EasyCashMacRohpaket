# (c) Copyright 2006-2012, 2014. CodeWeavers, Inc.
package CXMenuDtop;
use warnings;
use strict;
use CXLog;
use CXUtils;
use CXMenu;
use base "CXMenu";

# We keep a mapping from the regular folder path to the mangled folder
# path so we don't have to check the filesystem again and again.
my %mangled_folders;

sub create_mangled_folder($$$)
{
    my ($root, $parent, $component)=@_;

    my $new_folder;
    my $mangled=$mangled_folders{$component->{path}};
    if (!defined $mangled)
    {
        $mangled="$parent/" . mangle_string($component->{name});
        $mangled_folders{$component->{path}}=$mangled;
        $new_folder=1;
    }
    my $filename="$root$mangled/.directory";
    if ($new_folder or !$component->{intermediate} or !-f $filename)
    {
        my $dir="$root$mangled";
        if (!-d $dir and !mkdir($dir, 0777))
        {
            cxerr("unable to create the '$dir' directory: $!\n");
            return undef;
        }
        if (!CXMenu::xdg_create_directory($filename, $component, 1))
        {
            return undef;
        }
    }
    return $mangled;
}

sub new($$$$)
{
    my ($class, $cxoptions, $gui_info, $desktop)=@_;

    my $self={
        tag             => $cxoptions->{tag},
        destdir         => $cxoptions->{destdir},
        id              => $desktop,
        desktop         => "$cxoptions->{destdir}$desktop",
        xdg_dir         => "$cxoptions->{destdir}$gui_info->{xdg_preferred_data}",
    };
    if ($gui_info->{preferred_scope} eq "private")
    {
        $self->{xdg_dirs}=[$gui_info->{xdg_preferred_data}];
    }
    else
    {
        $self->{xdg_dirs}=[grep {$_ ne ""} split /:+/, $gui_info->{xdg_data_dirs}];
    }

    bless $self, $class;
    return $self;
}

sub detect($$$$)
{
    my ($class, $cxoptions, $cxconfig, $gui_info)=@_;

    my @selves;
    if ($gui_info->{dtop_on})
    {
        if ($gui_info->{dtop_preferred_desktop})
        {
            # This is the default XDG desktop
            push @selves, new($class, $cxoptions, $gui_info,
                              $gui_info->{dtop_preferred_desktop});
        }
        if ($gui_info->{dtop_preferred_alt_desktop})
        {
            # This is another XDG desktop (usually with a localized name)
            push @selves, new($class, $cxoptions, $gui_info,
                              $gui_info->{dtop_preferred_alt_desktop});
        }
    }
    return @selves;
}

sub id($)
{
    my ($self)=@_;
    my $id="CXMenuDtop/$self->{id}";
    $id =~ s%/+%/%g;
    return $id;
}

sub install($$)
{
    my ($self, $components)=@_;

    my $menu=@$components[-1];
    return 1 if (!$menu->{is_desktop});
    my $root=$self->{desktop};
    if (!cxmkpath($root))
    {
        cxerr("unable to create the '$root' directory: $@\n");
        return 0;
    }
    $self->{modified}=1;

    my $mangled="";
    foreach my $component (@$components)
    {
        $component->{_creator}="";
        CXMenu::xdg_install_icons($self->{xdg_dir}, $self->{tag}, $component);
        last if (!$component->{is_dir});
        $mangled=create_mangled_folder($root, $mangled, $component);
        return 0 if (!defined $mangled);
    }

    # Make sure our brand new (maybe empty) folder will not be
    # 'garbage collected' by finalize()
    $self->{status}->{$mangled}="in-use";

    if (!$menu->{is_dir})
    {
        $menu->{_categories}=undef;
        $menu->{_creator}=" (" . $self->id() . ")" if ($ENV{CX_TAGALL});
        my $filename=join("", $root, $mangled, "/",
                          mangle_string($menu->{name}), ".desktop");
        return 0 if (!CXMenu::xdg_create_desktop_file($filename, $menu));

        # Recent GNOME versions require the file to be marked as trusted
        # before it is treated as a .desktop file.
        if (defined CXUtils::cxwhich($ENV{PATH}, "gio") and
            cxsystem(("gio", "set", $filename, "metadata::trusted", "true")) == 0)
        {
            # Force GNOME to notice the above change
            my $now=time();
            utime $now, $now, $filename;
        }
    }
    return 1;
}

sub query($$)
{
    my ($self, $components)=@_;
    return ("", $self->id()) if (!defined $components);

    my $menu=@$components[-1];
    return "" if (!$menu->{is_desktop});

    my $path="$self->{desktop}$menu->{path}";
    $path.=($menu->{is_dir} ? "/.directory" : ".desktop");
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
    return [] if (!$menu->{is_desktop});

    my @files;
    foreach my $component (@$components)
    {
        push @files, @{CXMenu::xdg_get_icon_files($self->{destdir}, $self->{xdg_dirs}, $self->{tag}, $component)};
    }
    my $path="$self->{desktop}$menu->{path}";
    $path.=($menu->{is_dir} ? "/.directory" : ".desktop");
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

sub removeall_file($$$$)
{
    my ($self, $file, $pattern, $delete)=@_;

    foreach my $name ($file->get_section_names())
    {
        my $no_display=$file->get($name, "NoDisplay", "");
        if ($no_display =~ /^true$/i)
        {
            # This is not a menu (maybe an association?)
            cxlog(" -> not a menu\n");
            last;
        }
        my $created_by=$file->get($name, "X-Created-By");
        if (defined $created_by)
        {
            my @tags=grep !/^$pattern/, split /;+/, $created_by;
            if (@tags or !$delete)
            {
                $file->set($name, "X-Created-By", join(";", @tags));
                if (!$file->save())
                {
                    cxerr("unable to save '", $file->get_filename(), "'\n");
                }
                return "kept";
            }
            else
            {
                my $filename=$file->get_filename();
                cxlog("Deleting '$filename'\n");
                $self->{modified}=1;
                require CXRWConfig;
                CXRWConfig::uncache_file($filename);
                if (unlink $filename)
                {
                    return "deleted";
                }
                cxerr("unable to delete '$filename': $!\n");
            }
            last;
        }
    }
    return "kept";
}

sub removeall_folder($$$);
sub removeall_folder($$$)
{
    my ($self, $path, $pattern)=@_;

    my $directory;
    my $status="empty";
    if (opendir(my $dh, $path))
    {
        foreach my $dentry (readdir $dh)
        {
            next if ($dentry =~ /^\.\.?$/);
            $dentry="$path/$dentry";

            if (!-l $dentry and -d _)
            {
                if ($self->removeall_folder($dentry, $pattern) ne "deleted")
                {
                    $status="non-empty";
                }
            }
            elsif ($dentry =~ m%/\.directory$%)
            {
                require CXRWConfig;
                $directory=CXRWConfig->new($dentry, "xdg", "");
            }
            elsif ($dentry =~ m%\.desktop$%)
            {
                require CXRWConfig;
                my $file=CXRWConfig->new($dentry, "xdg", "");
                $status="non-empty" if ($self->removeall_file($file, $pattern, 1) ne "deleted");
            }
            else
            {
                $status="non-empty";
            }
        }
        closedir($dh);
    }
    if ($directory)
    {
        $status=$self->removeall_file($directory, $pattern, ($status eq "empty"));
        if ($status eq "deleted")
        {
            cxlog("Deleting the '$path' directory (empty)\n");
            $self->{modified}=1;
            if (!rmdir $path)
            {
                cxerr("unable to delete the '$path' directory: $!\n");
                $status="non-empty";
            }
            else
            {
                $status="deleted";
            }
        }
    }
    return $status;
}

sub uninstall($$)
{
    my ($self, $components)=@_;
    return 1 if ($self->{legacy_only});

    my $menu=@$components[-1];
    return 1 if (!$menu->{is_desktop});

    # Always consider the parent folder for deletion
    my $path=$menu->{dir};
    $self->{garbage_collect}->{$path}=1;

    $path="$self->{desktop}$path" . mangle_string($menu->{name});
    if ($menu->{is_dir})
    {
        if (-d $path)
        {
            cxlog("Deleting the '$path' directory\n");
            $self->removeall_folder($path, "$self->{tag}\$");
        }
    }
    else
    {
        $path.=".desktop";
        require CXRWConfig;
        CXRWConfig::uncache_file($path);
        if (-f $path)
        {
            cxlog("Deleting '$path'\n");
            $self->{modified}=1;
            if (!unlink $path)
            {
                cxerr("unable to delete '$path': $!\n");
                return 0;
            }
        }
    }
    return 1;
}

sub removeall($$)
{
    my ($self, $pattern)=@_;
    if ($pattern eq "legacy")
    {
        $pattern=CXUtils::get_product_id();
        $pattern="CrossOver Office" if ($pattern eq "cxoffice");
        $pattern.="\$";
    }
    elsif ($self->{legacy_only})
    {
        return 1;
    }
    $self->removeall_folder($self->{desktop}, $pattern);
    if ($pattern ne "legacy")
    {
        my $xdg_pattern="^cxmenu-$pattern";
        $xdg_pattern.=".*" if ($xdg_pattern !~ s/\$$//);
        for my $rawdir (@{$self->{xdg_dirs}})
        {
            my $dir="$self->{destdir}$rawdir";
            if (-d "$dir/icons")
            {
                CXUtils::delete_files("$dir/icons", "$xdg_pattern-.*\\.(?:png|xpm)\$", 1, 1);
                CXUtils::garbage_collect_subdirs($dir, "/icons", 1);
            }
        }
    }
    return 1;
}

sub gc_get_folder_status($$)
{
    my ($self, $path)=@_;
    my $root=$self->{desktop};

    # First check that folder's .directory file
    require CXRWConfig;
    my $directory=CXRWConfig->new("$root$path/.directory", "xdg", "");
    my @tags=split /;+/, $directory->get("Desktop Entry", "X-Created-By", "");
    # Skip folders that don't belong to this bottle
    return "alien" if (!grep /^$self->{tag}$/, @tags);

    my $status=(@tags == 1) ? "empty" : "non-empty";
    my @dirs=($path);
    while (@dirs)
    {
        my $dir=shift @dirs;
        my $dh;
        if (!opendir($dh, "$root$dir"))
        {
            cxlog("unable to open the '$root$dir' directory: $!\n");
            next;
        }
        foreach my $dentry (readdir $dh)
        {
            next if ($dentry =~ m/^\.\.?$/);
            $dentry="$dir/$dentry";
            next if ($dentry eq "$path/.directory");

            if (!-l "$root$dentry" and -d _)
            {
                if (!exists $self->{status}->{$dentry})
                {
                    push @dirs, $dentry;
                }
                elsif ($self->{status}->{$dentry} eq "in-use")
                {
                    cxlog(" 510: $dentry -> in-use\n");
                    closedir($dh);
                    return "in-use";
                }
            }
            elsif ($dentry =~ m%(?:/\.directory|\.desktop)$%)
            {
                require CXRWConfig;
                my $file=CXRWConfig->new("$root$dentry", "xdg", "");
                my $created_by;
                foreach my $name ($file->get_section_names())
                {
                    $created_by=$file->get($name, "X-Created-By");
                    next if (!defined $created_by);
                    cxlog("  $dentry -> $created_by\n");

                    if (grep /^$self->{tag}$/, split /;+/, $created_by)
                    {
                        cxlog(" 525: in-use tag=[$self->{tag}]\n");
                        closedir($dh);
                        return (undef, "in-use");
                    }
                }
            }
            cxlog(" 530: $dentry -> non-empty\n");
            $status="non-empty";
        }
        closedir($dh);

    }
    return $status;
}

sub gc_delete_folder($$$)
{
    my ($self, $path)=@_;
    $path="$self->{desktop}$path";

    cxlog("Deleting '$path/.directory'\n");
    require CXRWConfig;
    CXRWConfig::uncache_file("$path/.directory");
    if (!unlink "$path/.directory")
    {
        cxwarn("unable to delete '$path/.directory': $!\n");
    }

    cxlog("Deleting the '$path' directory (empty)\n");
    if (!rmdir $path)
    {
        cxwarn("unable to delete the '$path' directory: $!\n");
    }
}

sub gc_untag_folder($$$)
{
    my ($self, $path)=@_;
    $path="$self->{desktop}$path";

    require CXRWConfig;
    my $directory=CXRWConfig->new("$path/.directory", "xdg", "");
    my $section=$directory->get_section("Desktop Entry");
    my @tags=split /;+/, $section->get("X-Created-By");
    $section->set("X-Created-By", join(";", grep !/^$self->{tag}$/, @tags));
    if (!$directory->save())
    {
        cxwarn("unable to save '$path/.directory': $!\n");
    }
}

return 1;
