# (c) Copyright 2005, 2010. CodeWeavers, Inc.
package CXTinySAXLog;
use warnings;
use strict;
use CXTinySAXBase;
use base "CXTinySAXBase";
use CXLog;

# A handler that traces every call using CXLog
# which makes it possible to debug the parser.

sub init($)
{
    my ($self)=@_;
    $self->{indent}="";
    return $self->SUPER::init();
}

sub encoding($$)
{
    my ($self, $encoding)=@_;
    cxlog("encoding = $encoding\n");
    return 1;
}

sub start_element($$$)
{
    my ($self, $element, $attributes)=@_;
    cxlog("$self->{indent}<$element>\n");
    $self->{indent}.="  ";
    foreach my $key (keys %$attributes)
    {
        cxlog("$self->{indent}$key = $attributes->{$key}\n");
    }
    return 1;
}

sub end_element($$)
{
    my ($self, $element)=@_;
    $self->{indent} =~ s/  $//;
    return 1;
}

sub cdata($$$)
{
    my ($self, $element, $cdata)=@_;
    cxlog("$self->{indent}\[$cdata\]\n");
    return 1;
}

sub comment($$)
{
    my ($self, $comment)=@_;
    cxlog("$self->{indent}# $comment\n");
    return 1;
}

return 1;
