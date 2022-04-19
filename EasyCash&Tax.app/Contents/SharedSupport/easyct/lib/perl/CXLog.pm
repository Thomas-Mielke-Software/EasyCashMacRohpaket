# (c) Copyright 2003-2010. CodeWeavers, Inc.
package CXLog;
use warnings;
use strict;

# Define the module interface
use vars qw(@ISA @EXPORT);
use Exporter ();
@ISA    = "Exporter";
@EXPORT = qw(cxlog cxname0 cxwarn cxerr);


my $cx_log;
my $fh;
my $original_stderr;
my ($default_channel, $channels);

sub open($$)
{
    return undef if (defined $cx_log);
    $cx_log=$_[0];
    return undef if (!defined $cx_log);

    my $mode=$_[1] || ">>";
    if (CORE::open($fh, $mode, $cx_log))
    {
        my $tmp=select($fh); $| = 1; select($tmp); # Make unbuffered;
    }
    else
    {
        $cx_log=undef;
        $fh=undef;
    }
    return $fh;
}

sub fdopen($)
{
    return undef if (defined $cx_log);

    my ($fd)=@_;
    $cx_log="&=$fd";
    CORE::open($fh, ">>&=", $fd);
    return $fh;
}

sub close()
{
    if ($fh)
    {
        print $fh "Logging turned off\n";
        close($fh);
        $cx_log=undef;
        $fh=undef;
    }
    if (defined $original_stderr)
    {
        CORE::open(STDERR, ">&=", $original_stderr);
        CORE::close($original_stderr);
        $original_stderr=undef;
        my $tmp=select(STDERR); $| = 1; select($tmp); # Make unbuffered
    }
}

sub set_default_channel($)
{
    $default_channel=$_[0];
    if (!defined $channels->{$default_channel})
    {
        $channels->{$default_channel}=(defined $channels->{all} ? $channels->{all} : 1);
    }
}

sub get_filename()
{
    return $cx_log;
}

sub is_on(;$)
{
    my $channel=$_[0] || $default_channel;
    return ($fh and $channels->{$channel});
}

sub cxlog(@)
{
    print $fh @_ if (is_on());
}

sub cxlog_($@)
{
    my $channel=shift @_;
    print $fh @_ if (is_on($channel));
}

BEGIN {
    $channels = {};
    if (defined $ENV{CX_DEBUGMSG})
    {
        foreach my $chan_spec (split /,+/, $ENV{CX_DEBUGMSG})
        {
            $chan_spec =~ s/^([-+])//;
            $channels->{$chan_spec}=(($1 || "+") eq "+" ? 1 : 0);
        }
        $ENV{CX_LOG}="-" if (!defined $ENV{CX_LOG});
    }
    set_default_channel("cxscripts");
    if (!defined $ENV{CX_LOG})
    {
        # Nothing to do then
        ;
    }
    elsif ($ENV{CX_LOG} eq "-")
    {
        CXLog::fdopen(2);
        cxlog("\n\n");
        cxlog("***** ", scalar localtime(), "\n");
        cxlog("Starting: '", join("' '", $0, @ARGV), "'\n\n");
    }
    elsif (CXLog::open($ENV{CX_LOG}, ">>") or
           CXLog::open($ENV{CX_LOG}, ">") # Needed for fifos on Solaris
          )
    {
        cxlog("\n\n");
        cxlog("***** ", scalar localtime(), "\n");
        cxlog("Starting: '", join("' '", $0, @ARGV), "'\n\n");
        if (defined fileno(STDERR))
        {
            CORE::open($original_stderr, ">&", STDERR);
            CORE::open(STDERR, ">&=", $fh);
            my $tmp=select(STDERR); $| = 1; select($tmp); # Make unbuffered
        }
    }
}


#####
#
# Error and warning reporting interface
#
#####

sub cxname0()
{
    my $name0=$0;
    $name0 =~ s+^.*/++;
    return $name0;
}

sub cxwarn(@)
{
    print STDERR cxname0(), ":warning: ", @_;
    print $original_stderr cxname0(), ":warning: ", @_ if ($original_stderr);
}

sub cxerr(@)
{
    print STDERR cxname0(), ":error: ", @_;
    print $original_stderr cxname0(), ":error: ", @_ if ($original_stderr);
}

my $cxtime_hires;
sub cxtime()
{
    local $@;
    if (!defined $cxtime_hires)
    {
        $cxtime_hires=is_on() ? eval { require Time::HiRes } : 0;
    }
    return eval { Time::HiRes::time() } if ($cxtime_hires);
    return time();
}

return 1;
