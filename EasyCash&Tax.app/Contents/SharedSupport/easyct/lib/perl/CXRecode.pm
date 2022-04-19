# (c) Copyright 2005-2008, 2010. CodeWeavers, Inc.
package CXRecode;
use warnings;
use strict;

my $use_perl;
my $sys_encoding;
sub use_perl()
{
    if (!defined $use_perl)
    {
        $use_perl=eval "require Encode;";
        if ($@)
        {
            require CXLog;
            CXLog::cxlog("Unable to load 'Encode': $@\n");
        }

        require CXUtils;
        $sys_encoding=CXUtils::get_system_encoding();
    }
    return $use_perl;
}

my %cache;
sub recode_perl($$$)
{
    my ($src, $src_encoding, $dst_encoding)=@_;

    my $key=":$src_encoding:$dst_encoding:$src";
    my $dst=$cache{$key};
    if (!defined $dst)
    {
        $dst=$src;
        if ($src_encoding ne $dst_encoding)
        {
            eval { Encode::from_to($dst, $src_encoding, $dst_encoding, 1) };
            if ($@)
            {
                require CXLog;
                CXLog::cxlog("unable to convert '$src' from $src_encoding to $dst_encoding\n");
                $dst=$src;
            }
        }
        $cache{$key}=$dst;
    }
    return $dst;
}

sub recode_iconv($$$)
{
    my ($src, $src_encoding, $dst_encoding)=@_;

    my $key=":$src_encoding:$dst_encoding:$src";
    my $dst=$cache{$key};
    if (!defined $dst)
    {
        if ($src_encoding ne $dst_encoding)
        {
            require CXUtils;
            my $cmd="echo " . CXUtils::shquote_string($src) .
                " | iconv -f " . CXUtils::shquote_string($src_encoding) .
                " -t " . CXUtils::shquote_string($dst_encoding) . " 2>/dev/null";
            $dst=CXUtils::cxbackquote($cmd);
            if ($? == 0)
            {
                chomp $dst;
            }
            else
            {
                require CXLog;
                CXLog::cxlog("unable to convert '$src' from $src_encoding to $dst_encoding\n");
                $dst=$src;
            }
        }
        else
        {
            $dst=$src;
        }
        $cache{$key}=$dst;
    }
    return $dst;
}

sub recode($$$)
{
    my ($src, $src_encoding, $dst_encoding)=@_;
    return undef if (!defined $src);

    if (use_perl())
    {
        return recode_perl($src, $src_encoding, $dst_encoding);
    }
    return recode_iconv($src, $src_encoding, $dst_encoding);

}

sub to_sys($$)
{
    my ($src_encoding, $src)=@_;
    return undef if (!defined $src);

    if (use_perl())
    {
        return recode_perl($src, $src_encoding, $sys_encoding);
    }
    return recode_iconv($src, $src_encoding, $sys_encoding);
}

sub from_sys($$)
{
    my ($dst_encoding, $src)=@_;
    return undef if (!defined $src);

    if (use_perl())
    {
        return recode_perl($src, $sys_encoding, $dst_encoding);
    }
    return recode_iconv($src, $sys_encoding, $dst_encoding);
}

return 1;
