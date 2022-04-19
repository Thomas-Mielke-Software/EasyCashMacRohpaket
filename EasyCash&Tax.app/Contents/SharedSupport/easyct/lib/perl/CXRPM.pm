# (c) Copyright 2006-2008, 2010. CodeWeavers, Inc.
package CXRPM;
use warnings;
use strict;

use CXLog;
use CXUtils;


#####
#
# Static functions
#
#####

sub compute_package_name($)
{
    my ($name)=@_;
    $name =~ s/[ <>=]/_/g;
    return $name;
}

sub escape_file_path($)
{
    my ($path)=@_;
    # This is the status with rpm 4.4.2.3:
    # - Paths containing a space must be enclosed in quotes. Quoting just the
    #   space or any form of escaping does not work.
    # - '*' must be escaped by enclosing it in square brackets. It will still
    #   trigger a 'file listed twice' warning but it will work regardless.
    # - '!', '#', '$', '%', '&', '(', ')', ';', '<', '>', '[', '\', ']', '`',
    # '{', '|' and '}' also trigger the same warning but don't need escaping.
    # - ''' and '"' must not be quoted and must not be escaped.
    # - If a path contains both a space and a single or double quote...
    #   well, let's hope this does not happen.
    $path =~ s/(\*)/[$1]/g;
    return "\"$path\"" if ($path =~ / /);
    return $path;
}


#####
#
# The CXRPM class
#
#####

sub new($)
{
    my ($class)=@_;
    my $self={ };
    bless $self, $class;

    $self->{rpmbuild}=CXUtils::cxwhich($ENV{PATH}, "rpmbuild");
    if (!defined $self->{rpmbuild})
    {
        $self->{warn}="You may need to install some rpm development " .
                      "packages such as rpm-build";
        $self->{rpmbuild}=CXUtils::cxwhich($ENV{PATH}, "rpm");
        if (!defined $self->{rpmbuild})
        {
            cxerr("unable to find rpmbuild or rpm - $self->{warn}\n");
            cxerr("cannot build the RPM packages\n");
        }
    }

    return $self;
}

sub get_rpm_version($)
{
    my ($self)=@_;
    return cxbackquote(shquote_string($self->{rpmbuild}) . " --version 2>&1");
}

sub map_directory($$$$)
{
    my ($self, $root, $dir, $mode)=@_;
    # Return undef to not package the directory
    # Otherwise return the destination path and desired mode
    return ($dir, $mode);
}

sub map_file($$$$)
{
    my ($self, $root, $file, $mode)=@_;
    # Return undef to not package the file
    # Otherwise return the destination path and desired mode
    return ($file, $mode);
}

sub create_image($$$)
{
    my ($self, $src, $dstroot)=@_;
    # On SuSE 8.0 rpm 3.0.6 has a bug which is triggered
    # by using hardlinks to copy the source directory
    my $nolinks=($self->get_rpm_version() =~ /\s3\./);

    if (!cxmkpath($dstroot, 0700))
    {
        cxerr("unable to create the '$dstroot' directory: $@\n");
        return 0;
    }
    my $mode=(stat($src))[2] & 07777;
    chmod($mode, $dstroot);

    my @dirs=("");
    while (@dirs)
    {
        my $dir=shift @dirs;
        cxlog("$dir\n");

        my $dh;
        if (!opendir($dh, "$src/$dir"))
        {
            cxerr("unable to open the '$src/$dir' directory: $!\n");
            return 0;
        }
        foreach my $dentry (readdir $dh)
        {
            next if ($dentry =~ /^\.\.?$/);
            $dentry="$dir$dentry";

            my $mode=(lstat("$src/$dentry"))[2];
            if (-l _)
            {
                my ($dst, $dmode, $gunzip)=$self->map_file($src, $dentry, $mode);
                if (!defined $dst)
                {
                    cxlog("ignoring $dentry\n");
                    next;
                }
                if ($gunzip)
                {
                    cxerr("not decompressing symbolic links '$dentry'\n");
                    return 0;
                }
                my $lnk=readlink "$src/$dentry";
                if (!symlink $lnk, "$dstroot/$dst")
                {
                    cxerr("unable to symlink '$dstroot/$dst' to '$lnk': $!\n");
                    return 0;
                }
            }
            elsif (-d _)
            {
                my ($dst, $dmode)=$self->map_directory($src, $dentry, $mode);
                next if (!defined $dst);
                if (!mkdir("$dstroot/$dst", 0700))
                {
                    cxerr("unable to create the '$dstroot/$dst' directory: $!\n");
                    return 0;
                }
                chmod($dmode & 07777, "$dstroot/$dst");
                push @dirs, "$dentry/";
            }
            else
            {
                my ($dst, $dmode, $gunzip)=$self->map_file($src, $dentry, $mode);
                next if (!defined $dst);
                if (($dmode != $mode) or $nolinks or $gunzip or
                    !link "$src/$dentry", "$dstroot/$dst")
                {
                    require File::Copy;
                    if (!File::Copy::copy("$src/$dentry", "$dstroot/$dst"))
                    {
                        cxerr("unable to copy '$src/$dentry' to '$dstroot/$dst': $!\n");
                        return 0;
                    }
                    chmod($dmode & 07777, "$dstroot/$dst");
                }
                if ($gunzip and cxsystem(CXUtils::get_gzip(), "-d", "$dstroot/$dst"))
                {
                    cxerr("unable to decompress '$dstroot/$dst'\n");
                    return 0;
                }
            }
        }
        closedir($dh);
    }
    return 1;
}

sub build($$;$)
{
    my ($self, $rpmdir, $arch)=@_;
    return 1 if (!defined $self->{rpmbuild});

    my @cmd=(shquote_string($self->{rpmbuild}), "-bb");
    push @cmd, "--buildroot", shquote_string("$rpmdir/image") if ($self->{rpmbuild} =~ /rpmbuild$/);
    push @cmd, "--target", $arch if ($arch);
    push @cmd, "--define", shquote_string("_rpmdir $rpmdir"),
               shquote_string("$rpmdir/rpm.spec"), "2>&1";
    my $output=cxbackquote(join(" ", @cmd));
    if ($?)
    {
        print STDERR $output;
        cxwarn("$self->{rpmbuild} failed - $self->{warn}\n") if ($self->{warn});
    }
    return $?;
}

return 1;
