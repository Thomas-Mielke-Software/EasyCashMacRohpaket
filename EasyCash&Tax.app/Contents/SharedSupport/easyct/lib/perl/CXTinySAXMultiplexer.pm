# (c) Copyright 2005, 2010. CodeWeavers, Inc.
package CXTinySAXMultiplexer;
use warnings;
use strict;
use CXTinySAXBase;
use base "CXTinySAXBase";

# A handler that calls multiple handlers in turn until one returns false.

sub new($$)
{
    my ($class, $handlers)=@_;
    my $self={ handlers => $handlers };
    bless $self, $class;
    return undef if (!$self->init());
    return $self;
}

sub encoding($$)
{
    my ($self, $encoding)=@_;
    foreach my $handler (@{$self->{handlers}})
    {
        return 0 if (!$handler->encoding($encoding));
    }
    return 1;
}

sub start_element($$$)
{
    my ($self, $element, $attributes)=@_;
    foreach my $handler (@{$self->{handlers}})
    {
        return 0 if (!$handler->start_element($element, $attributes));
    }
    return 1;
}

sub end_element($$)
{
    my ($self, $element)=@_;
    foreach my $handler (@{$self->{handlers}})
    {
        return 0 if (!$handler->end_element($element));
    }
    return 1;
}

sub cdata($$$)
{
    my ($self, $element, $cdata)=@_;
    foreach my $handler (@{$self->{handlers}})
    {
        return 0 if (!$handler->cdata($element, $cdata));
    }
    return 1;
}

sub comment($$)
{
    my ($self, $comment)=@_;
    foreach my $handler (@{$self->{handlers}})
    {
        return 0 if (!$handler->comment($comment));
    }
    return 1;
}

return 1;
