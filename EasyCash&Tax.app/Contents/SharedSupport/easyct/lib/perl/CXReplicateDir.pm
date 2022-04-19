# (c) Copyright 2002-2008, 2010. CodeWeavers, Inc.
package CXReplicateDir;
use warnings;
use strict;

use CXLog;
use CXUtils;


#
# Functions for building and saving file lists
#

sub scan_tree($;$)
{
    my ($rootdir, $re_skip)=@_;
    $rootdir.="/" if ($rootdir !~ m%/$%);
    my $types={};
    my $timestamps={};
    my $links={};

    cxlog("\nScanning '$rootdir':\n");
    my @dirs=("");
    while (@dirs)
    {
        my $dh;
        my $dir=shift @dirs;
        cxlog("$dir\n") if ($dir ne "");
        if (!opendir($dh, "$rootdir$dir"))
        {
            cxerr("unable to read '$rootdir$dir': $!\n");
            return 1;
        }
        foreach my $dentry (readdir $dh)
        {
            next if ($dentry =~ /^\.\.?$/);
            $dentry="$dir$dentry";

            if (defined $re_skip and $dentry =~ /$re_skip/)
            {
                cxlog("skipping '$dentry'\n");
                next;
            }

            my @st=stat("$rootdir$dentry");
            if (@st)
            {
                if (-d _)
                {
                    if (-l "$rootdir$dentry")
                    {
                        my $link=readlink("$rootdir$dentry");
                        $types->{$dentry}="l->d";
                        $links->{$dentry}=$link;
                    }
                    else
                    {
                        $types->{$dentry}="d";
                        push @dirs, "$dentry/";
                    }
                }
                elsif (-f _ or -b _)
                {
                    $timestamps->{$dentry}=$st[9];
                    if (-l "$rootdir$dentry")
                    {
                        my $link=readlink("$rootdir$dentry");
                        $types->{$dentry}="l->f";
                        $links->{$dentry}=$link;
                    }
                    else
                    {
                        $types->{$dentry}="f";
                    }
                }
                else
                {
                    cxlog("ignoring '$dentry' (not a file or directory)\n");
                }
            }
            else
            {
                cxwarn("ignoring dead link '$rootdir$dentry'\n");
            }
        }
        closedir($dh);
    }
    return { types => $types,
             timestamps => $timestamps,
             links => $links
           };
}

sub read_file_list($)
{
    my ($file)=@_;
    my $types={};
    my $links={};

    my $in;
    if (!open($in, "<", $file))
    {
        cxerr("unable to open '$file' for reading: $!\n");
    }
    else
    {
        while (<$in>)
        {
            if (/^(\S+) (.*)$/)
            {
                my ($type, $entry)=($1, $2);
                $entry =~ s%/$%%;
                if ($type eq "d")
                {
                    $types->{$entry}="d";
                }
                elsif ($type =~ s/^l->d=//)
                {
                    $types->{$entry}="l->d";
                    $links->{$entry}=demangle_string($type);
                }
                elsif ($type =~ s/^l->f=//)
                {
                    $types->{$entry}="l->f";
                    $links->{$entry}=demangle_string($type);
                }
                else
                {
                    $types->{$entry}="f";
                    # We don't care about the timestamp for old files
                }
            }
        }
        close($in);
    }
    return { types => $types,
             links => $links
           };
}

sub write_file_list($$)
{
    my ($file, $list)=@_;

    my $out;
    if (!open($out, ">", $file))
    {
        cxerr("unable to open '$file' for writing: $!\n");
        return;
    }
    my $types=$list->{types};
    foreach my $entry (sort keys %$types)
    {
        my $type=$types->{$entry};
        if ($type eq "f")
        {
            print $out "$list->{timestamps}->{$entry} $entry\n";
        }
        elsif ($type eq "d")
        {
            print $out "d $entry\n";
        }
        else
        {
            print $out "$type=", mangle_string($list->{links}->{$entry}), " $entry\n";
        }
    }
    close($out);
}


#
# CXReplicateDir initialization
#

sub new($$$)
{
    my ($class, $refdir, $dstdir)=@_;
    my $self={ refdir => $refdir,
               dstdir => $dstdir };
    bless $self, $class;
    return $self;
}

sub set_link_type($$)
{
    my ($self, $linktype)=@_;
    if (!defined $linktype)
    {
        $linktype="symbolic";
    }
    else
    {
        $linktype =~ s/\s*//;
        $linktype =~ tr/A-Z/a-z/;
    }

    if ($linktype eq "symbolic" or $linktype eq "symbolic,hard")
    {
        $self->{dolink}=\&do_link_symbolic;
    }
    elsif ($linktype eq "hard")
    {
        $self->{dolink}=\&do_link_hard;
    }
    elsif ($linktype eq "hard,symbolic")
    {
        $self->{dolink}=\&do_link_hard_symbolic;
    }
    else
    {
        cxwarn("ignoring invalid LinkType specification '$linktype'\n");
        $self->{dolink}=\&do_link_symbolic;
    }
}

sub set_full_copy($$)
{
    my ($self, $full_copy)=@_;
    $self->{full_copy}=$full_copy;
}

sub set_policy_settings($$$)
{
    my ($self, $section, $validate)=@_;

    if ($section)
    {
        cxlog("Policy list:\n");
        foreach my $regexp (@{$section->get_field_list()})
        {
            my $policy=$section->get($regexp);
            $policy =~ s/\s*//;
            $policy =~ tr/A-Z/a-z/;
            if ($validate)
            {
                # Check that the policy is valid
                my $count=0;
                my $delignore=0;
                foreach my $flag (split /,/, $policy)
                {
                    if ($flag =~ /^(?:delete|ignore)$/)
                    {
                        $count++;
                        $delignore|=1;
                    }
                    elsif ($flag =~ /^(?:link|linkdir|copy|registry)$/)
                    {
                        $count++;
                    }
                    elsif ($flag !~ /^(?:replacefiles|replacedirs|replaceconflicting)$/)
                    {
                        cxwarn("ignoring invalid policy '$policy'\n");
                        $policy=undef;
                        last;
                    }
                    else
                    {
                        $delignore|=2;
                    }
                }
                if ($count != 1 or $delignore == 3)
                {
                    cxwarn("ignoring invalid policy '$policy'\n");
                    $policy=undef;
                }
            }
            if ($policy)
            {
                cxlog("  $regexp -> $policy\n");
                push @{$self->{policy_list}}, $regexp if ($regexp ne ".*");
                $self->{policies}->{$regexp}=$policy;
            }
        }
    }
    $self->{default_policy}=$self->{policies}->{".*"} || "link";
    delete $self->{policies}->{".*"};
}


#
# Merge actions
#

sub action_noop($$)
{
    return "recurse";
}

sub action_skip($$)
{
    # Skip the sub-directories
    return "skip";
}

sub action_cp($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_cp}}, $entry;
    return "recurse";
}

sub action_cpr($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_mkdir}}, $entry;
    # Return recurse so the recursive copy will simply happen
    # as a side-effect of the caller's loop.
    return "recurse";
}

sub action_ln($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_ln}}, $entry;
    return "recurse";
}

sub action_lns($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_lns}}, $entry;
    # Skip the sub-directories
    return "skip";
}

sub action_cpln($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_cpln}}, [$entry, $cxreplicate->{new}->{links}->{$entry}];
    return "recurse";
}

sub action_regoverride($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_regoverride}}, $entry;
    return "recurse";
}

sub action_regpreserve($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_regpreserve}}, $entry;
    return "recurse";
}

sub action_ifeq_rm($$)
{
    my ($cxreplicate, $entry)=@_;
    my $old=$cxreplicate->{old}->{links}->{$entry};
    if (defined $old and $old eq $cxreplicate->{link})
    {
        push @{$cxreplicate->{to_rm}}, $entry;
    }
    return "recurse";
}

sub action_ifne_cpln($$)
{
    my ($cxreplicate, $entry)=@_;
    my $link=$cxreplicate->{new}->{links}->{$entry};
    if ($link ne $cxreplicate->{link})
    {
        push @{$cxreplicate->{to_rm}}, $entry;
        push @{$cxreplicate->{to_cpln}}, [$entry, $link];
    }
    return "recurse";
}

sub action_chk_cpln($$)
{
    my ($cxreplicate, $entry)=@_;
    my $new=$cxreplicate->{new}->{links}->{$entry};
    if ($cxreplicate->{link} ne $new)
    {
        my $old=$cxreplicate->{old}->{links}->{$entry};
        if (defined $old and $cxreplicate->{link} eq $old)
        {
            push @{$cxreplicate->{to_rm}}, $entry;
            push @{$cxreplicate->{to_cpln}}, [$entry, $new];
        }
    }
    return "recurse";
}

sub action_rm($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_rm}}, $entry;
    return "recurse";
}

sub action_rm_cp($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_rm}}, $entry;
    push @{$cxreplicate->{to_cp}}, $entry;
    return "recurse";
}

sub action_rm_ln($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_rm}}, $entry;
    push @{$cxreplicate->{to_ln}}, $entry;
    return "recurse";
}

sub action_rm_cpln($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_rm}}, $entry;
    push @{$cxreplicate->{to_cpln}}, [$entry, $cxreplicate->{new}->{links}->{$entry}];
    return "recurse";
}

sub action_rm_new($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_rm}}, $entry;
    while (my ($old_entry, $old_type) = each %{$cxreplicate->{old}->{types}})
    {
        delete $cxreplicate->{old}->{types}->{$old_entry} if index($old_entry, $entry) == 0;
    }
    # Return 'ignore' so this entry will not be put in
    # the 'stub' list, and so we skip the sub-directories.
    return "ignore";
}

sub action_rmdir($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_rmdir}}, $entry;
    return "recurse";
}

sub action_rmrf($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_rmtree}}, $entry;
    # Skip the sub-directories
    return "skip";
}

sub action_rmrf_new($$)
{
    my ($cxreplicate, $entry)=@_;
    push @{$cxreplicate->{to_rmtree}}, $entry;
    delete $cxreplicate->{old}->{types}->{$entry};
    # Return 'ignore' so this entry will not be put in
    # the 'stub' list, and so we skip the sub-directories.
    return "ignore";
}

sub action_update($$)
{
    my ($cxreplicate, $entry)=@_;
    if ($cxreplicate->{stamp} < $cxreplicate->{new}->{timestamps}->{$entry})
    {
        push @{$cxreplicate->{to_cp}}, $entry;
    }
    return "recurse";
}


#
# File merges
#

sub get_file_merge_column($)
{
    my ($policy)=@_;
    if ($policy =~ /link/)
    {
        return "link+replacefiles" if ($policy =~ /replacefiles/);
        return "link";
    }
    elsif ($policy =~ /registry/)
    {
        return "registry+replacefiles" if ($policy =~ /replacefiles/);
        return "registry";
    }
    # else $policy =~ /copy/
    return "copy+replacefiles" if ($policy =~ /replacefiles/);
    return "copy";
}

my $file_merge_n_n_f=
{"link"                  => \&action_ln,
 "link+replacefiles"     => \&action_ln,
 "copy"                  => \&action_cp,
 "copy+replacefiles"     => \&action_cp,
 "registry"              => \&action_cp,
 "registry+replacefiles" => \&action_cp
};
my $file_merge_e_n_f=
{"link"                  => \&action_noop,
 "link+replacefiles"     => \&action_ln,
 "copy"                  => \&action_noop,
 "copy+replacefiles"     => \&action_cp,
 "registry"              => \&action_cp,
 "registry+replacefiles" => \&action_cp
};
my $file_merge_f_f=
{"link"                  => \&action_noop,
 "link+replacefiles"     => \&action_rm_ln,
 "copy"                  => \&action_noop,
 "copy+replacefiles"     => \&action_update,
 "registry"              => \&action_regpreserve,
 "registry+replacefiles" => \&action_regoverride
};
my $file_merge_lf_f=
{"link"                  => \&action_noop,
 "link+replacefiles"     => \&action_rm_ln,
 "copy"                  => \&action_noop,
 "copy+replacefiles"     => \&action_rm_cp,
 "registry"              => \&action_rm_cp,
 "registry+replacefiles" => \&action_rm_cp
};
my $file_merge_lmf_f=
{"link"                  => \&action_noop,
 "link+replacefiles"     => \&action_noop,
 "copy"                  => \&action_rm_cp,
 "copy+replacefiles"     => \&action_rm_cp,
 "registry"              => \&action_rm_cp,
 "registry+replacefiles" => \&action_rm_cp
};
my $file_merge_ln_f=
{"link"                  => \&action_rm_ln,
 "link+replacefiles"     => \&action_rm_ln,
 "copy"                  => \&action_rm_cp,
 "copy+replacefiles"     => \&action_rm_cp,
 "registry"              => \&action_rm_cp,
 "registry+replacefiles" => \&action_rm_cp
};
my $file_merge_n_f_n=
{"link"                  => \&action_noop,
 "link+replacefiles"     => \&action_noop,
 "copy"                  => \&action_noop,
 "copy+replacefiles"     => \&action_noop,
 "registry"              => \&action_noop,
 "registry+replacefiles" => \&action_noop
};
my $file_merge_n_ln_n=
{"link"                  => \&action_rm,
 "link+replacefiles"     => \&action_rm,
 "copy"                  => \&action_rm,
 "copy+replacefiles"     => \&action_rm,
 "registry"              => \&action_rm,
 "registry+replacefiles" => \&action_rm
};
my $file_merge_e_f_n=
{"link"                  => \&action_rm,
 "link+replacefiles"     => \&action_rm,
 "copy"                  => \&action_rm,
 "copy+replacefiles"     => \&action_rm,
 "registry"              => \&action_rm,
 "registry+replacefiles" => \&action_rm
};
my $file_merge_e_lf_n=
{"link"                  => \&action_ifeq_rm,
 "link+replacefiles"     => \&action_rm,
 "copy"                  => \&action_ifeq_rm,
 "copy+replacefiles"     => \&action_rm,
 "registry"              => \&action_rm,
 "registry+replacefiles" => \&action_rm
};
my $file_merge={         "-;-;f"        => $file_merge_n_n_f,
                         "e;-;f"        => $file_merge_e_n_f,
                         "-;f;f"        => $file_merge_f_f,
                         "e;f;f"        => $file_merge_f_f,
                         "-;l->f;f"     => $file_merge_lf_f,
                         "e;l->f;f"     => $file_merge_lf_f,
                         "-;l->mf;f"    => $file_merge_lmf_f,
                         "e;l->mf;f"    => $file_merge_lmf_f,
                         "-;l->-;f"     => $file_merge_ln_f,
                         "e;l->-;f"     => $file_merge_ln_f,
                         "-;f;-"        => $file_merge_n_f_n,
                         "-;l->f;-"     => $file_merge_n_f_n,
                         "-;l->-;-"     => $file_merge_n_ln_n,
                         "e;f;-"        => $file_merge_e_f_n,
                         "e;l->-;-"     => $file_merge_e_f_n,
                         "e;l->f;-"     => $file_merge_e_lf_n
               };


#
# File Symbolic Link merges
#

sub get_linkfile_merge_column($)
{
    return get_file_merge_column($_[0]);
}

my $linkfile_merge_n_n_lf=
{"link"                  => \&action_cpln,
 "link+replacefiles"     => \&action_cpln,
 "copy"                  => \&action_cp,
 "copy+replacefiles"     => \&action_cp,
 "registry"              => \&action_cp,
 "registry+replacefiles" => \&action_cp
};
my $linkfile_merge_e_n_lf=
{"link"                  => \&action_noop,
 "link+replacefiles"     => \&action_cpln,
 "copy"                  => \&action_noop,
 "copy+replacefiles"     => \&action_cp,
 "registry"              => \&action_cp,
 "registry+replacefiles" => \&action_cp
};
my $linkfile_merge_f_lf=
{"link"                  => \&action_noop,
 "link+replacefiles"     => \&action_rm_cpln,
 "copy"                  => \&action_noop,
 "copy+replacefiles"     => \&action_update,
 "registry"              => \&action_regpreserve,
 "registry+replacefiles" => \&action_regoverride
};
my $linkfile_merge_n_lf_lf=
{"link"                  => \&action_noop,
 "link+replacefiles"     => \&action_ifne_cpln,
 "copy"                  => \&action_noop,
 "copy+replacefiles"     => \&action_rm_cp,
 "registry"              => \&action_rm_cp,
 "registry+replacefiles" => \&action_rm_cp
};
my $linkfile_merge_e_lf_lf=
{"link"                  => \&action_chk_cpln,
 "link+replacefiles"     => \&action_ifne_cpln,
 "copy"                  => \&action_noop,
 "copy+replacefiles"     => \&action_rm_cp,
 "registry"              => \&action_rm_cp,
 "registry+replacefiles" => \&action_rm_cp
};
my $linkfile_merge_lmf_lf=
{"link"                  => \&action_rm_cpln,
 "link+replacefiles"     => \&action_rm_cpln,
 "copy"                  => \&action_rm_cp,
 "copy+replacefiles"     => \&action_rm_cp,
 "registry"              => \&action_rm_cp,
 "registry+replacefiles" => \&action_rm_cp
};
my $linkfile_merge={     "-;-;l->f"     => $linkfile_merge_n_n_lf,
                         "e;-;l->f"     => $linkfile_merge_e_n_lf,
                         "-;f;l->f"     => $linkfile_merge_f_lf,
                         "e;f;l->f"     => $linkfile_merge_f_lf,
                         "-;l->f;l->f"  => $linkfile_merge_n_lf_lf,
                         "e;l->f;l->f"  => $linkfile_merge_e_lf_lf,
                         "-;l->mf;l->f" => $linkfile_merge_lmf_lf,
                         "e;l->mf;l->f" => $linkfile_merge_lmf_lf,
                         "-;l->-;l->f"  => $linkfile_merge_lmf_lf,
                         "e;l->-;l->f"  => $linkfile_merge_lmf_lf
                   };


#
# Directory merges
#

sub get_directory_merge_column($)
{
    my ($policy)=@_;
    if ($policy =~ /linkdir/)
    {
        return "linkdir+replacedirs" if ($policy =~ /replacedirs/);
        return "linkdir";
    }
    # else $policy =~ /(link|copy|registry)/
    return "link+replacedirs" if ($policy =~ /replacedirs/);
    return "link";
}

my $directory_merge_n_n_d=
{"link"                  => \&action_cpr,
 "link+replacedirs"      => \&action_cpr,
 "linkdir"               => \&action_lns,
 "linkdir+replacedirs"   => \&action_lns
};
my $directory_merge_e_n_d=
{"link"                  => \&action_noop,
 "link+replacedirs"      => \&action_cpr,
 "linkdir"               => \&action_noop,
 "linkdir+replacedirs"   => \&action_lns
};
my $directory_merge_d_d=
{"link"                  => \&action_noop,
 "link+replacedirs"      => \&action_noop,
 "linkdir"               => \&action_noop,
 "linkdir+replacedirs"   => \&action_rmrf_new
};
my $directory_merge_ld_d=
{"link"                  => \&action_noop,
 "link+replacedirs"      => \&action_rm_new,
 "linkdir"               => \&action_noop,
 "linkdir+replacedirs"   => \&action_rm_new
};
my $directory_merge_lmd_d=
{"link"                  => \&action_noop,
 "link+replacedirs"      => \&action_rm_new,
 "linkdir"               => \&action_noop,
 "linkdir+replacedirs"   => \&action_noop
};
my $directory_merge_ln_d=
{"link"                  => \&action_rm_new,
 "link+replacedirs"      => \&action_rm_new,
 "linkdir"               => \&action_rm_new,
 "linkdir+replacedirs"   => \&action_rm_new
};
my $directory_merge_n_d_n=
{"link"                  => \&action_noop,
 "link+replacedirs"      => \&action_noop,
 "linkdir"               => \&action_noop,
 "linkdir+replacedirs"   => \&action_noop
};
my $directory_merge_n_ld_n=
{"link"                  => \&action_noop,
 "link+replacedirs"      => \&action_noop,
 "linkdir"               => \&action_noop,
 "linkdir+replacedirs"   => \&action_noop
};
my $directory_merge_e_d_n=
{"link"                  => \&action_rmdir,
 "link+replacedirs"      => \&action_rmrf,
 "linkdir"               => \&action_rmrf,
 "linkdir+replacedirs"   => \&action_rmrf
};
my $directory_merge_e_ld_n=
{"link"                  => \&action_ifeq_rm,
 "link+replacedirs"      => \&action_rm,
 "linkdir"               => \&action_ifeq_rm,
 "linkdir+replacedirs"   => \&action_rm
};
my $directory_merge={    "-;-;d"        => $directory_merge_n_n_d,
                         "e;-;d"        => $directory_merge_e_n_d,
                         "-;d;d"        => $directory_merge_d_d,
                         "e;d;d"        => $directory_merge_d_d,
                         "-;l->d;d"     => $directory_merge_ld_d,
                         "e;l->d;d"     => $directory_merge_ld_d,
                         "-;l->md;d"    => $directory_merge_lmd_d,
                         "e;l->md;d"    => $directory_merge_lmd_d,
                         "-;l->-;d"     => $directory_merge_ln_d,
                         "e;l->-;d"     => $directory_merge_ln_d,
                         "-;d;-"        => $directory_merge_n_d_n,
                         "-;l->d;-"     => $directory_merge_n_ld_n,
                         "e;d;-"        => $directory_merge_e_d_n,
                         "e;l->d;-"     => $directory_merge_e_ld_n
                    };


#
# Directory Symbolic Link merges
#

sub get_linkdir_merge_column($)
{
    my ($policy)=@_;
    return "link+replacedirs" if ($policy =~ /replacedirs/);
    return "link";
}

my $linkdir_merge_n_n_ld=
{"link"                  => \&action_cpln,
 "link+replacedirs"      => \&action_cpln
};
my $linkdir_merge_e_n_ld=
{"link"                  => \&action_noop,
 "link+replacedirs"      => \&action_cpln
};
my $linkdir_merge_d_ld=
{"link"                  => \&action_skip,
 "link+replacedirs"      => \&action_rmrf_new
};
my $linkdir_merge_ld_ld=
{"link"                  => \&action_chk_cpln,
 "link+replacedirs"      => \&action_chk_cpln
};
my $linkdir_merge_lmd_ld=
{"link"                  => \&action_rm_cpln,
 "link+replacedirs"      => \&action_rm_cpln
};
my $linkdir_merge={      "-;-;l->d"     => $linkdir_merge_n_n_ld,
                         "e;-;l->d"     => $linkdir_merge_e_n_ld,
                         "-;d;l->d"     => $linkdir_merge_d_ld,
                         "e;d;l->d"     => $linkdir_merge_d_ld,
                         "-;l->d;l->d"  => $linkdir_merge_ld_ld,
                         "e;l->d;l->d"  => $linkdir_merge_ld_ld,
                         "-;l->md;l->d" => $linkdir_merge_lmd_ld,
                         "e;l->md;l->d" => $linkdir_merge_lmd_ld,
                         "-;l->-;l->d"  => $linkdir_merge_lmd_ld,
                         "e;l->-;l->d"  => $linkdir_merge_lmd_ld
                    };


#
# Conflict merges
#

sub get_conflict_merge_column($)
{
    my ($policy)=@_;
    return ($policy =~ /replaceconflicting/ ? "replaceconflicting" : "link");
}

my $conflict_merge_f_d=
{"link"                  => \&action_noop,
 "replaceconflicting"    => \&action_rm_new
};
my $conflict_merge_d_f=
{"link"                  => \&action_skip,
 "replaceconflicting"    => \&action_rmrf_new
};
my $conflict_merge_ld_f=
{"link"                  => \&action_noop,
 "replaceconflicting"    => \&action_rm_new
};
my $conflict_merge={     "-;f;d"        => $conflict_merge_f_d,
                         "e;f;d"        => $conflict_merge_f_d,
                         "-;l->f;d"     => $conflict_merge_f_d,
                         "e;l->f;d"     => $conflict_merge_f_d,
                         "-;f;l->d"     => $conflict_merge_f_d,
                         "e;f;l->d"     => $conflict_merge_f_d,
                         "-;l->f;l->d"  => $conflict_merge_f_d,
                         "e;l->f;l->d"  => $conflict_merge_f_d,
                         "-;d;f"        => $conflict_merge_d_f,
                         "e;d;f"        => $conflict_merge_d_f,
                         "-;d;l->f"     => $conflict_merge_d_f,
                         "e;d;l->f"     => $conflict_merge_d_f,
                         "-;l->d;f"     => $conflict_merge_ld_f,
                         "e;l->d;f"     => $conflict_merge_ld_f,
                         "-;l->d;l->f"  => $conflict_merge_ld_f,
                         "e;l->d;l->f"  => $conflict_merge_ld_f
                    };


#
# The merge engine
#

sub merge_tree_get_policy($$)
{
    my ($self, $entry)=@_;
    foreach my $regexp (@{$self->{policy_list}})
    {
        return $self->{policies}->{$regexp} if ($entry =~ /$regexp/i);
    }
    return $self->{default_policy};
}

sub merge_tree($;$)
{
    my ($self, $re_skip)=@_;
    my $dstdir=$self->{dstdir};
    $dstdir.="/" if ($dstdir !~ m%/$%);
    my $refdir=$self->{refdir};
    $refdir.="/" if ($refdir !~ m%/$%);

    my $old=$self->{old}->{types};
    my $new=$self->{new}->{types};
    my $stub;

    # Merge existing files
    cxlog("\nMerging files in '$dstdir':\n");
    my @dirs=("");
    while (@dirs)
    {
        my $dh;
        my $dir=shift @dirs;
        if (!opendir($dh, "$dstdir$dir"))
        {
            cxerr("unable to read '$dstdir$dir': $!\n");
            return 1;
        }
        foreach my $dentry (readdir $dh)
        {
            next if ($dentry =~ /^\.\.?$/);
            $dentry="$dir$dentry";
            next if (defined $re_skip and $dentry =~ /$re_skip/);

            # Determine which policy applies to this entry
            my $policy=$self->merge_tree_get_policy($dentry);

            # Handle the 'delete' and 'ignore' policies
            if ($policy eq "delete")
            {
                if (-d "$dstdir$dentry")
                {
                    cxlog("$dentry\t(d) delete\n");
                    push @{$self->{to_rmtree}}, $dentry;
                }
                else
                {
                    cxlog("$dentry\t(f) delete\n");
                    push @{$self->{to_rm}}, $dentry;
                }
                $stub->{$dentry}="delete";
                next;
            }
            if ($policy eq "ignore")
            {
                cxlog("$dentry\t(?) ignore\n");
                $stub->{$dentry}="ignore";
                next;
            }

            # Determine what's the type/timestamp of this entry
            my $type;
            my @st=stat("$dstdir$dentry");
            if (@st)
            {
                if (-f _)
                {
                    $type="f";
                }
                elsif (-d _)
                {
                    $type="d";
                }
                else
                {
                    cxwarn("ignoring special file '$dstdir$dentry'\n");
                    $stub->{$dentry}="special";
                    next;
                }
                if (-l "$dstdir$dentry")
                {
                    $self->{link}=readlink("$dstdir$dentry");
                    if ($self->{link} ne "$refdir$dentry")
                    {
                        if ($self->{link} =~ m%\Q$refdir\Efake_windows/%)
                        {
                            # Force the old links to be recreated
                            $type="l->-";
                        }
                        else
                        {
                            $type="l->$type";
                        }
                    }
                    else
                    {
                        if (!exists $new->{$dentry})
                        {
                            # Force the links to be recreated if they
                            # only work on a case-insensitive filesystem.
                            $type="l->-";
                        }
                        else
                        {
                            $type="l->m$type";
                        }
                    }
                }
                else
                {
                    $self->{stamp}=$st[9];
                }
            }
            else
            {
                $type="l->-";
            }

            # If doing a full copy then tweak the policy here
            # so that the user ends up with a standalone copy
            if ($self->{full_copy})
            {
                if ($type =~ /^l->m[fd]$/)
                {
                    $policy="copy,replacedirs,replacefiles";
                }
                elsif ($policy =~ /(?:link|linkdir)/)
                {
                    $policy =~ s/replace(?:files|dirs),//g;
                    $policy =~ s/,replace(?:files|dirs)//g;
                }
            }

            # Determine which merge action to take
            my ($table, $line, $column);
            $line=join(";",
                       (exists $old->{$dentry} ? "e" : "-"),
                       $type,
                       (exists $new->{$dentry} ? $new->{$dentry} : "-"));

            if ($type =~ /d/)
            {
                if (!defined $new->{$dentry} or $new->{$dentry} eq "d")
                {
                    $table=$directory_merge;
                    $column=get_directory_merge_column($policy);
                }
                elsif (defined $new->{$dentry} and $new->{$dentry} eq "l->d")
                {
                    $table=$linkdir_merge;
                    $column=get_linkdir_merge_column($policy);
                }
                else
                {
                    $table=$conflict_merge;
                    $column=get_conflict_merge_column($policy);
                }
            }
            elsif ($type =~ /f/)
            {
                if (defined $new->{$dentry} and $new->{$dentry} =~ /^(?:d|l->d)$/)
                {
                    $table=$conflict_merge;
                    $column=get_conflict_merge_column($policy);
                }
                elsif (defined $new->{$dentry} and $new->{$dentry} eq "l->f")
                {
                    $table=$linkfile_merge;
                    $column=get_linkfile_merge_column($policy);
                }
                else
                {
                    $table=$file_merge;
                    $column=get_file_merge_column($policy);
                }
            }
            else
            {
                if (defined $new->{$dentry} and $new->{$dentry} eq "d")
                {
                    $table=$directory_merge;
                    $column=get_directory_merge_column($policy);
                }
                elsif (defined $new->{$dentry} and $new->{$dentry} eq "l->d")
                {
                    $table=$linkdir_merge;
                    $column=get_linkdir_merge_column($policy);
                }
                elsif (defined $new->{$dentry} and $new->{$dentry} eq "l->f")
                {
                    $table=$linkfile_merge;
                    $column=get_linkfile_merge_column($policy);
                }
                else
                {
                    $table=$file_merge;
                    $column=get_file_merge_column($policy);
                }
            }

            # Do the merge
            cxlog("$dentry\t($line) $policy\n");
            my $rc=&{$table->{$line}->{$column}}($self, $dentry);
            if ($rc ne "ignore")
            {
                $stub->{$dentry}=$type;
                push @dirs, "$dentry/" if ($type eq "d" and $rc ne "skip");
            }
        }
        closedir($dh);
    }


    # Create new files
    cxlog("\nMerging new files from '$refdir':\n");
    my $skip;
    foreach my $entry (sort keys %$new)
    {
        # Skip sub-directory trees if told to
        next if (defined $skip and $entry =~ /^\Q$skip\E/);
        $skip=undef;
        next if (defined $re_skip and $entry =~ /$re_skip/);

        # Skip existing files and directories
        if (defined $stub->{$entry})
        {
            if ($new->{$entry} eq "d" and $stub->{$entry} eq "l->md")
            {
                # If the destination entry is a symbolic link to the
                # corresponding reference directory, then skip the
                # sub-directories since they are going to match anyway.
                $skip="$entry/";
            }
            next;
        }

        # Determine which policy applies to this entry
        my $policy=$self->merge_tree_get_policy($entry);

        # Handle the 'delete' and 'ignore' policies
        if ($policy =~ /(?:delete|ignore)/)
        {
            # Skip sub-directories if any
            $skip="$entry/";
            next;
        }

        # If doing a full copy, then tweak the policy here
        # so that the user ends up with a standalone copy
        $policy="copy,replacedirs,replacefiles" if ($self->{full_copy});

        # Determine which merge action to take
        my ($table, $line, $column);
        $line=(exists $old->{$entry} ? "e" : "-") . ";-;$new->{$entry}";
        if ($new->{$entry} eq "d")
        {
            $table=$directory_merge;
            $column=get_directory_merge_column($policy);

        }
        elsif ($new->{$entry} eq "l->d")
        {
            $table=$linkdir_merge;
            $column=get_linkdir_merge_column($policy);
        }
        elsif ($new->{$entry} eq "l->f")
        {
            $table=$linkfile_merge;
            $column=get_linkfile_merge_column($policy);
        }
        else
        {
            $table=$file_merge;
            $column=get_file_merge_column($policy);
        }

        # Do the merge
        cxlog("$entry\t($line) $policy\n");
        my $rc=&{$table->{$line}->{$column}}($self, $entry);
        $skip="$entry/" if ($rc ne "recurse");
    }
}


#
# Functions to dump the task list (for debugging)
#

sub dump_list($$)
{
    my ($msg, $list)=@_;

    if ($list and @$list)
    {
        cxlog("$msg:\n");
        foreach my $entry (sort @$list)
        {
            cxlog("   $entry\n");
        }
        cxlog("\n");
        return 1;
    }
    return 0;
}

sub dump_array_list($$)
{
    my ($msg, $list)=@_;

    if ($list and @$list)
    {
        cxlog("$msg:\n");
        foreach my $entry (sort @$list)
        {
            my ($src, $dst)=@$entry;
            cxlog("   $src -> $dst\n");
        }
        cxlog("\n");
        return 1;
    }
    return 0;
}

sub dump_task_list($)
{
    my ($self)=@_;
    if (CXLog::is_on())
    {
        cxlog("Task list:\n");
        my $rc=0;
        $rc|=dump_list("mkdir", $self->{to_mkdir});
        $rc|=dump_list("rmdir", $self->{to_rmdir});
        $rc|=dump_list("rm -rf", $self->{to_rmtree});
        $rc|=dump_list("rm", $self->{to_rm});
        $rc|=dump_list("ln", $self->{to_ln});
        $rc|=dump_list("ln -s", $self->{to_lns});
        $rc|=dump_array_list("cpln", $self->{to_cpln});
        $rc|=dump_list("cp", $self->{to_cp});
        $rc|=dump_list("regpreserve", $self->{to_regpreserve});
        $rc|=dump_list("regoverride", $self->{to_regoverride});
        cxlog("Nothing to do\n") if (!$rc);
    }
}


#
# Functions to do the merge
#

sub do_link_symbolic($$)
{
    my ($src, $dst)=@_;
    return symlink($src, $dst);
}

sub do_link_hard($$)
{
    my ($src, $dst)=@_;
    return link($src, $dst);
}

sub do_link_hard_symbolic($$)
{
    my ($src, $dst)=@_;
    return 1 if (link($src, $dst));
    return 1 if (symlink($src, $dst));
    return 0;
}

sub do_regappend($$)
{
    my ($src, $dst)=@_;
    my $in;
    return 0 if (!open($in, "<", $src));
    my $out;
    if (!open($out, ">>", $dst))
    {
        close($in);
        return 0;
    }
    # Skip the first line to avoid warnings when Wine starts
    my $skip=1;
    my $oldline;
    while (my $line=<$in>)
    {
        if ($line =~ /^\[/)
        {
            $oldline=$line;
            $skip=undef;
        }
        elsif ($line =~ /^#link/)
        {
            # Duplicated registry symbolic links confuse wineserver. Ideally
            # we'd check if they are already present in the first half of the
            # file but since we don't know what's there we just skip them.
            $skip=1;
        }
        elsif (!$skip)
        {
            if (defined $oldline)
            {
                print $out $oldline;
                $oldline=undef;
            }
            print $out $line;
        }
    }
    close($in);
    close($out);
    return 1;
}

sub apply_changes($)
{
    my ($self)=@_;
    my $refdir=$self->{refdir};
    my $dstdir=$self->{dstdir};

    # Delete old files
    if ($self->{to_rm})
    {
        foreach my $entry (@{$self->{to_rm}})
        {
            if (!unlink "$dstdir/$entry")
            {
                cxwarn("unable to delete '$dstdir/$entry': $!\n");
            }
        }
    }

    # Delete old directories
    if ($self->{to_rmdir})
    {
        foreach my $entry (sort {$b cmp $a} @{$self->{to_rmdir}})
        {
            # We only use rmdir to delete directories that might be empty.
            # So it's ok if it fails.
            rmdir "$dstdir/$entry";
        }
    }
    if ($self->{to_rmtree})
    {
        require File::Path;
        foreach my $entry (sort {$b cmp $a} @{$self->{to_rmtree}})
        {
            if (-d "$dstdir/$entry" and !File::Path::rmtree("$dstdir/$entry"))
            {
                cxwarn("unable to delete the '$dstdir/$entry' directory: $!\n");
            }
        }
    }

    # Create new directories
    if ($self->{to_mkdir})
    {
        foreach my $entry (sort @{$self->{to_mkdir}})
        {
            if (!mkdir("$dstdir/$entry", 0777))
            {
                cxwarn("unable to create the '$dstdir/$entry' directory: $!\n");
            }
        }
    }

    # Create symbolic links (to directories)
    if ($self->{to_lns})
    {
        foreach my $entry (@{$self->{to_lns}})
        {
            my $rc=do_link_symbolic("$refdir/$entry", "$dstdir/$entry");
            if (!$rc)
            {
                cxwarn("unable to link '$dstdir/$entry': $!\n");
            }
        }
    }

    # Create links to files
    if ($self->{to_ln})
    {
        my $dolink=$self->{dolink};
        foreach my $entry (@{$self->{to_ln}})
        {
            my $rc=&$dolink("$refdir/$entry", "$dstdir/$entry");
            if (!$rc)
            {
                cxwarn("unable to link '$dstdir/$entry': $!\n");
            }
        }
    }

    # Replicate symbolic links
    if ($self->{to_cpln})
    {
        foreach my $entry (@{$self->{to_cpln}})
        {
            my ($src, $dst)=@$entry;
            my $rc=do_link_symbolic($dst, "$dstdir/$src");
            if (!$rc)
            {
                cxwarn("unable to link '$dstdir/$src' to '$dst': $!\n");
            }
        }
    }

    # Copy new files
    if ($self->{to_cp})
    {
        my $now=time;
        require File::Copy;
        # Setuid and setgid don't make sense for bottle files and
        # are dangerous. So remove them. Allow the sticky bit though.
        # Also apply the user's umask since these will be his files.
        my $modmask=01777 & ~umask();
        foreach my $entry (@{$self->{to_cp}})
        {
            if (File::Copy::copy("$refdir/$entry", "$dstdir/$entry"))
            {
                # Preserve the modification time and the permissions
                utime $now, $self->{new}->{timestamps}->{$entry}, "$dstdir/$entry";
                my $perms=(stat("$refdir/$entry"))[2];
                
                $perms = $perms | 0600 if ($perms & 0400);
                $perms = $perms | 0660 if ($perms & 0440);

                chmod($perms & $modmask, "$dstdir/$entry");
            }
            else
            {
                cxwarn("unable to copy '$dstdir/$entry': $!\n");
            }
        }
    }

    # Merge the registry, preserving the user modifications
    if ($self->{to_regpreserve})
    {
        require File::Copy;
        foreach my $entry (@{$self->{to_regpreserve}})
        {
            if (!rename("$dstdir/$entry", "$dstdir/$entry.$$"))
            {
                cxwarn("unable to merge '$dstdir/$entry' (preserve/rename): $!\n");
                next;
            }
            if (!File::Copy::copy("$refdir/$entry", "$dstdir/$entry"))
            {
                cxwarn("unable to merge '$dstdir/$entry' (preserve/copy): $!\n");
                rename("$dstdir/$entry.$$", "$dstdir/$entry");
                next;
            }
            if (!do_regappend("$dstdir/$entry.$$", "$dstdir/$entry"))
            {
                cxwarn("unable to merge '$dstdir/$entry' (preserve/regappend)\n");
                rename("$dstdir/$entry.$$", "$dstdir/$entry");
            }
            else
            {
                unlink("$dstdir/$entry.$$");
            }
        }
    }

    # Merge the registry, overriding the user modifications
    if ($self->{to_regoverride})
    {
        require File::Copy;
        foreach my $entry (@{$self->{to_regoverride}})
        {
            if (!File::Copy::copy("$dstdir/$entry", "$dstdir/$entry.$$"))
            {
                cxwarn("unable to merge '$dstdir/$entry' (override/copy): $!\n");
                next;
            }
            if (!do_regappend("$refdir/$entry", "$dstdir/$entry"))
            {
                cxwarn("unable to merge '$dstdir/$entry' (override/regappend)\n");
                rename("$dstdir/$entry.$$", "$dstdir/$entry");
            }
            else
            {
                unlink("$dstdir/$entry.$$");
            }
        }
    }
}

return 1;
