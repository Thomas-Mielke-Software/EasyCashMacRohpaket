# (c) Copyright 2008, 2010, 2014. CodeWeavers, Inc.
package CXDebian;
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

    # Debian packages only allow a precisely defined
    # set of characters in the package name.
    $name =~ tr/A-Z/a-z/;
    $name =~ s/[^a-z0-9+.-]/+/g;
    return $name;
}


#####
#
# The CXDebian class
#
#####

sub new($$)
{
    my ($class, $buildroot)=@_;
    my $self={ buildroot => $buildroot,
               renames => 0
             };
    bless $self, $class;

    my %tools=("dh_builddeb"       => "debhelper",
               "dpkg-buildpackage" => "dpkg-dev",
               "fakeroot"          => "fakeroot");

    my @missing;
    while (my ($tool, $package)=each %tools)
    {
        $self->{$tool}=CXUtils::cxwhich($ENV{PATH}, $tool);
        push @missing, $package if (!defined $self->{$tool});
    }
    if (@missing)
    {
        cxerr("You need to install some Debian development packages: " . join(", ", @missing) . " or equivalent\n");
        return undef;
    }

    if (!cxmkpath("$self->{buildroot}/debian", 0700))
    {
        cxerr("unable to create the '$self->{buildroot}/debian' directory: $@\n");
        return undef;
    }

    return $self;
}

sub add_file($$)
{
    my ($self, $src_root, $src)=@_;

    my $dst=$self->map_file($src_root, $src);
    if (!defined $dst)
    {
        cxlog("  $src -> <undef>\n");
        return 1;
    }
    cxlog("  $src -> $dst\n");

    my $full_src="$src_root/$src";
    my $src_base=cxbasename($src);
    my $dst_base=cxbasename($dst);
    if ($src =~ / / or $dst =~ / / or $dst_base ne $src_base)
    {
        if (!defined $self->{staged}->{$dst})
        {
            # Put the file in a staging directory because dh_install cannot
            # handle spaces or renaming.
            if (!defined $self->{stagingdir})
            {
                $self->{stagingdir}="$self->{buildroot}/staging";
                if (!mkdir $self->{stagingdir})
                {
                    cxerr("unable to create the '$self->{stagingdir}' directory: $!\n");
                    return 0;
                }
                push @{$self->{install}}, "$self->{stagingdir}/* /\n";
            }

            require File::Copy;
            my $staging="$self->{stagingdir}$dst";
            my $stagingdir=cxdirname($staging);
            if (!cxmkpath($stagingdir))
            {
                cxerr("unable to create the '$stagingdir' directory: $@\n");
                return 0;
            }
            if (!link("$full_src", $staging) and
                !File::Copy::copy("$full_src", $staging))
            {
                cxerr("unable to link/copy '$full_src' to '$staging': $!\n");
                return 0;
            }
            $self->{staged}->{$dst}=$full_src;
        }
        elsif ($self->{staged}->{$dst} ne $full_src)
        {
            cxerr("cannot ship both '$self->{staged}->{$dst}' and '$full_src' as '$dst'\n");
            return 0;
        }
    }
    else
    {
        $dst=cxdirname($dst);
        push @{$self->{install}}, "$full_src $dst\n";
    }
    return 1;
}

sub add_tree($$)
{
    my ($self, $src_root)=@_;
    cxlog("Debian::add_tree($src_root)\n");

    my @dirs=("");
    while (@dirs)
    {
        my $dir=shift @dirs;
        cxlog("$dir\n");

        my $dh;
        if (!opendir($dh, "$src_root/$dir"))
        {
            cxerr("unable to open the '$src_root/$dir' directory: $!\n");
            return 0;
        }
        foreach my $dentry (readdir $dh)
        {
            next if ($dentry =~ /^\.\.?$/);
            my $src="$dir$dentry";

            if (!-l "$src_root/$src" and -d _)
            {
                my $mode=(stat(_))[2] & 07777;
                my $dst=$self->map_directory($src_root, $src);
                if (!defined $dst)
                {
                    cxlog("  $src -> <undef>\n");
                    next;
                }
                cxlog("  $src -> $dst\n");
                if ($dst)
                {
                    push @{$self->{install}}, "$src_root/$src/* $dst\n";
                }
                else
                {
                    push @dirs, "$src/";
                }
            }
            elsif (!$self->add_file($src_root, $src))
            {
                return 0;
            }
        }
        closedir($dh);
    }
    return 1;
}

sub build($;@)
{
    my $self=shift @_;

    if (open(my $fh, ">", "$self->{buildroot}/debian/install"))
    {
        print $fh @{$self->{install}};
        close($fh);
    }
    else
    {
        cxerr("unable to open '$self->{buildroot}/debian/install' for writing: $!\n");
        return 0;
    }

    my $cmd=join(" ", shquote_string($self->{fakeroot}),
                 shquote_string("$self->{buildroot}/debian/build"),
                 shquote_string($self->{buildroot}), @_, "2>&1");
    my $output=cxbackquote($cmd);
    if ($?)
    {
        print STDERR $output;
        cxwarn("unable to build the Debian package\n");
        if ($self->{buildroot} =~ / /)
        {
            cxwarn("this is most likely because the path contains a space: '$self->{buildroot}'\n");
        }
        return 1;
    }
    return 0;
}

return 1;
