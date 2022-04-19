# (c) Copyright 2005, 2010. CodeWeavers, Inc.
package CXTinySAXBase;
use warnings;
use strict;

# This is the base class for CXTinySAX handlers.
# Actual handlers should inherit from this class and
# then implement the functions they care about.

sub new($)
{
    my ($class)=@_;
    my $self={};
    bless $self, $class;
    return undef if (!$self->init());
    return $self;
}

sub init($)
{
    #my ($self)=@_;
    return 1;
}

sub encoding($$)
{
    #my ($self, $encoding)=@_;
    return 1;
}

sub start_element($$$)
{
    #my ($self, $element, $attributes)=@_;
    return 1;
}

sub end_element($$)
{
    #my ($self, $element)=@_;
    return 1;
}

sub cdata($$$)
{
    #my ($self, $element, $cdata)=@_;
    return 1;
}

sub comment($$)
{
    #my ($self, $comment)=@_;
    return 1;
}

return 1;
