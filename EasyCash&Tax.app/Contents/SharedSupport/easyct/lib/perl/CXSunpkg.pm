# (c) Copyright 2006-2010. CodeWeavers, Inc.
package CXSunpkg;
use warnings;
use strict;
use CXLog;
use CXUtils;



#####
#
# Static functions
#
#####

sub pkg_sum($)
{
    my ($filename)=@_;
    my $fh;
    if (!open($fh, "<", $filename))
    {
        cxerr("unable to open '$filename' for reading: $!\n");
        return "";
    }

    my $rs=$/;
    $/=undef;
    my $checksum = unpack("%32C*", <$fh>) % 65535;
    close($fh);
    $/=$rs;
    return $checksum;
}

sub compute_package_name($$)
{
    my ($prefix, $name)=@_;

    # Some Solaris 10 has a 32 character limit on package names.
    # (For Solaris 8 and older the limit is 9 characters!)
    my $max=32-length($prefix);

    my $pkg=$name;
    $pkg =~ s/^managed_//;
    if (length($pkg) > $max or $pkg =~ /^clientp?$/)
    {
        $pkg=substr($pkg, 0, $max-2) . CXUtils::base32(CXUtils::hash_string($name), 2);
    }
    return "$prefix$pkg";
}

sub is_valid_zip_format($)
{
    my ($format)=@_;
    return ($format =~ /^(?:none|bzip2|gzip|7z)$/);
}


#####
#
# The CXSunpkg class
#
#####

sub new($$$)
{
    my ($class, $pkgdir, $compress)=@_;
    return if (!is_valid_zip_format($compress));

    if (!cxmkpath("$pkgdir/install", 0755))
    {
        cxerr("unable to create the '$pkgdir/install' directory: $@\n");
        return;
    }

    my $self={pkgmap   => ["13"],
              pkgdir   => $pkgdir,
              compress => $compress
             };

    bless $self, $class;
    return $self;
}

sub package_directory($$$$)
{
    my ($self, $root, $dir, $mode)=@_;
    # Return undef to not package the directory
    # Otherwise return the desired mode
    return $mode;
}

sub package_file($$$$)
{
    my ($self, $root, $file, $mode)=@_;
    # Return undef to not package the file
    # Otherwise return the desired mode
    return $mode;
}

sub add_symlink($$$)
{
    my ($self, $rlink, $rdst)=@_;
    $rlink=~s!^reloc/!!;
    push @{$self->{pkgmap}}, "1 s none $rlink=$rdst";
    return 1;
}

sub add_file($$$;$$)
{
    my ($self, $type, $rfile, $src, $mode)=@_;
    my $pkgmap=$self->{pkgmap};

    my $dst="$self->{pkgdir}/$rfile";
    if (defined $src)
    {
        require File::Copy;
        if (!File::Copy::copy($src, $dst))
        {
            cxerr("unable to copy '$src' to '$dst': $!\n");
            return 0;
        }
        # No need to set the mode here, it will be set
        # at install time based on pkgmap
    }

    my ($size, $mtime)=(stat($dst))[7,9];
    my $chksum=pkg_sum($dst);
    if ($type eq "i")
    {
        $rfile =~ s!install/!!;
        push @$pkgmap, "1 i $rfile $size $chksum $mtime";
    }
    else
    {
        $rfile=~s!^reloc/!!;
        $mode=sprintf "%04o", $mode & 07777;
        push @$pkgmap, "1 f none $rfile $mode root bin $size $chksum $mtime";
    }
    @$pkgmap[0]+=1+($size >> 9);
    return 1;
}

sub add_dir($$$)
{
    my ($self, $rdir, $mode)=@_;
    my $pkgmap=$self->{pkgmap};

    my $dir="$self->{pkgdir}/$rdir";
    if (!cxmkpath($dir, $mode))
    {
        cxerr("unable to create the '$dir' directory: $@\n");
        return 0;
    }

    $rdir=~s!^reloc/!!;
    $mode=sprintf "%04o", $mode & 07777;
    push @{$self->{pkgmap}}, "1 d none $rdir $mode root bin";
    return 1;
}

sub add_tree($$$$)
{
    my ($self, $rdir, $srcdir, $mode)=@_;

    my @dirs=("", $mode);
    while (@dirs)
    {
        my $dir=shift @dirs;
        $mode=shift @dirs;
        cxlog("dir=$dir\n");
        return 0 if (!$self->add_dir("$rdir/$dir", $mode));

        my $dh;
        if (!opendir($dh, "$srcdir/$dir"))
        {
            cxerr("unable to open the '$srcdir/$dir' directory: $!\n");
            return 0;
        }
        $dir.="/" if($dir ne "");
        my $rc=1;
        foreach my $dentry (readdir $dh)
        {
            next if ($dentry =~ /^\.\.?$/);
            $dentry="$dir$dentry";

            $mode=(lstat("$srcdir/$dentry"))[2];
            if (-l _)
            {
                my $dmode=$self->package_file($srcdir, $dentry, $mode);
                next if (!defined $dmode);
                my $dst=readlink "$srcdir/$dentry";
                $rc=$self->add_symlink("$rdir/$dentry", $dst);
            }
            elsif (-d _)
            {
                my $dmode=$self->package_directory($srcdir, $dentry, $mode);
                next if (!defined $dmode);
                push @dirs, $dentry, $dmode;
            }
            else
            {
                my $dmode=$self->package_file($srcdir, $dentry, $mode);
                next if (!defined $dmode);
                $rc=$self->add_file("f", "$rdir/$dentry", "$srcdir/$dentry", $dmode);
            }
            last if (!$rc);

            if ($dentry =~ /[ =]/)
            {
                $dentry=~ s!^/!!;
                cxerr("cannot package '$dentry'\n");
                cxerr("Solaris packages cannot handle paths containing spaces or equal signs\n");
                return 0;
            }
        }
        closedir($dh);
        return 0 if (!$rc);
    }
    return 1;
}

sub generate_install_files($$$$)
{
    my ($self, $template, $files, $variables)=@_;

    push @$files, "install/i.none" if ($self->{compress} ne "none");
    foreach my $file (@$files)
    {
        my $rc=CXUtils::generate_from_template("$self->{pkgdir}/$file",
                                               $template . cxbasename($file),
                                               $variables);
        return 0 if ($rc);
        return 0 if (!$self->add_file("i", $file));
    }
    return 1;
}

sub finalize($$)
{
    my ($self, $relocdir)=@_;
    my $pkgmap=$self->{pkgmap};
    @$pkgmap[0]=": 1 @$pkgmap[0]";

    my $fh;
    if (!open($fh, ">", "$self->{pkgdir}/pkgmap"))
    {
        cxerr("unable to open '$self->{pkgdir}/pkgmap' for writing: $!\n");
        return 0;
    }
    print $fh join("\n", @$pkgmap), "\n";
    close($fh);

    if ($self->{compress} ne "none")
    {
        my $archive="$self->{pkgdir}/archive";
        if (!cxmkpath($archive, 0755))
        {
            cxerr("unable to create the '$archive' directory: $!\n");
            return 0;
        }

        $relocdir="$self->{pkgdir}/reloc/$relocdir";
        my $cmd=[["cd", $relocdir], "&&",
                 [["find", ".", "-print"],
                  "|",
                  [[CXUtils::get_cpio_o()], "2>"] # cpio pollutes stderr
                 ]];
        if ($self->{compress} eq "gzip")
        {
            $cmd=[$cmd, "|", [[CXUtils::get_gzip(), "-9"], ">", "$archive/none.gz"]];
        }
        elsif ($self->{compress} eq "bzip2")
        {
            $cmd=[$cmd, "|", [[CXUtils::get_bzip2(), "-9"], ">", "$archive/none.bz2"]];
        }
        elsif ($self->{compress} eq "7z")
        {
            # 7za -si pollutes stderr
            $cmd=[$cmd, "|", [["7za", "a", "-mx=9", "-si", "$archive/none.7z"], "2>"]];
        }

        my $shcmd=new_shell_command({cmd => $cmd, capture_output => 1});
        if ($shcmd->run())
        {
            print STDERR $shcmd->get_error_report();
            cxerr("the package compression failed\n");
            return 0;
        }

        require File::Path;
        if (!File::Path::rmtree($relocdir))
        {
            cxerr("unable to delete the '$relocdir' directory: $!\n");
            return 0;
        }
    }
    return 1;
}

return 1;
