package HTML::FillInForm;

use integer; # no floating point math so far!
use strict; # and no funny business, either.

use Carp; # generate better errors with more context

use HTML::Parser 3;

# required for UNIVERSAL->can
require 5.005;

use vars qw($VERSION @ISA);
$VERSION = '0.02';
@ISA = qw(HTML::Parser);

sub new {
  my ($class) = @_;
  my $self = bless {}, $class;
  $self->init;
  $self->boolean_attribute_value('__BOOLEAN__');
  return $self;
}

# a few shortcuts to fill()
sub fill_file { my $self = shift; return $self->fill('file',@_); }
sub fill_arrayref { my $self = shift; return $self->fill('arrayref',@_); }
sub fill_scalarref { my $self = shift; return $self->fill('scalarref',@_); }

sub fill {
  my ($self, %option) = @_;

  if(my $object = $option{fobject}){
#    foreach my $object (@objects){
      # make sure objects in 'param_object' parameter support param()
    defined($object->can('param')) or
      croak("HTML::FillInForm->fillInForm called with fobject option, containing object of type " . ref($object) . " which lacks a param() method!");
    foreach my $key ($object->param()){
      $self->{fdat}->{$key} = $object->param($key);
    }
#    }
  }
  if (my $fdat = $option{fdat}){
    $self->{fdat} = $fdat;
  }

  # get data set from param() method
  foreach my $key ($self->param){
    $self->{fdat}->{$key} = $self->param($key);
  }

  # make sure method has data to fill in HTML form with!
  unless($self->{fdat}){
    croak("HTML::FillInForm->fillInForm() called without 'object' or 'fdat' parameter set");
  }

  if(my $file = $option{file}){
    $self->parse_file($file);
  } elsif (my $scalarref = $option{scalarref}){
    $self->parse($$scalarref);
#    return $$scalarref;
  } elsif (my $arrayref = $option{arrayref}){
    for (@$arrayref){
      $self->parse($_);
    }
  }
  return $self->{output};
}

# handles opening HTML tags such as <input ...>
sub start {
  my ($self, $tag, $attr, $attrseq, $origtext) = @_;
  if ($tag =~ m/^(input|option)$/){
    if ($tag eq 'input'){
      if (my $value = $self->{fdat}->{$attr->{'name'}}){
	if ($attr->{'type'} =~ /^(text|textfield|hidden|password)$/){
	  $attr->{'value'} = $self->escapeHTML($value);
	} elsif ($attr->{'type'} eq 'radio'){
	  if ($attr->{'value'} eq $value){
	    $attr->{'checked'} = '__BOOLEAN__';
	  } else {
	    delete $attr->{'checked'};
	  }
	}
      }
    } elsif ($tag eq 'option'){
      if($attr->{'value'} eq $self->{fdat}->{$self->{selectName}}){
	$attr->{selected} = '__BOOLEAN__';
      } else {
	delete $attr->{selected} if exists $attr->{selected};
      }
    }
    $self->{output} .= "<$tag";
    foreach my $key (keys %$attr) {
      if($attr->{$key} eq '__BOOLEAN__'){
	# boolean attribute
	$self->{output} .= " $key";
      } else {
	$self->{output} .= " $key" . qq(="$attr->{$key}");
      }
    }
    $self->{output} .= ">";
  } elsif ($tag eq 'textarea'){
    if (my $value = $self->{fdat}->{$attr->{'name'}}){
      # <textarea> foobar </textarea> -> <textarea> $value <textarea>
      # we need to set outputText to 'no' so that 'foobar' won't be printed
      $self->{outputText} = 'no';
      $self->{output} .= $origtext . $value;
    } else {
      $self->{output} .= $origtext;
    }
  } elsif ($tag eq 'select'){
    $self->{selectName} = $attr->{'name'};
    $self->{output} .= $origtext;
  } else {
    $self->{output} .= $origtext;
  }
}

# handles non-html text
sub text {
  my ($self, $origtext) = @_;
  # just output text, unless replaced value of <textarea> tag
  unless($self->{outputText} eq 'no'){
    $self->{output} .= $origtext;
  }
}

# handles closing HTML tags such as </textarea>
sub end {
  my ($self, $tag, $origtext) = @_;
  if($tag eq 'select'){
    delete $self->{selectName};
  } elsif ($tag eq 'textarea'){
    delete $self->{outputText};
  }
  $self->{output} .= $origtext;
}

sub escapeHTML {
  my ($self, $toencode) = @_;

  return undef unless defined($toencode);
  $toencode =~ s/&/&amp;/g;
  $toencode =~ s/\"/&quot;/g;
  $toencode =~ s/>/&gt;/g;
  $toencode =~ s/</&lt;/g;
  return $toencode;
}

# param method - can be called in two forms
# when passed two arguments ($name, $value), it sets the value of the 
# $name attributes to $value
# when passwd one argument ($name), retrives the value of the $name attribute
sub param {
  my ($self, @p) = @_;
  unless(@p){
    return () unless defined($self) && $self->{'.parameters'};
    return () unless @{$self->{'.parameters'}};
    return @{$self->{'.parameters'}};
  }
  my ($name, $value);
  if (@p > 1){
    ($name, $value) = @p;
    $self->add_parameter($name);
    $self->{param}->{$name} = $value;
  } else {
    $name = $p[0];
  }

  return $self->{param}->{$name};
}

sub add_parameter {
  my ($self, $param) = @_;
  return unless defined $param;
  push (@{$self->{'.parameters'}},$param)
    unless defined($self->{$param});
}

1;

__END__

=head1 NAME

HTML::FillInForm - Populates HTML Forms with CGI data.

=head1 DESCRIPTION

This module automatically inserts data from a previous HTML form into the HTML input, textarea and select tags.
It is a subclass of L<HTML::Parser> and uses it to parse the HTML and insert the values into the form tags.

One useful application is after a user submits an HTML form without filling out
required field.  HTML::FillInForm can be used to redisplay the HTML form
with all the form elements containing the submitted info.

=head1 SYNOPSIS

This examples fills data into a HTML form stored in C<$htmlForm> from CGI parameters that are stored
in C<$q>.  For example, it will set the value of any "name" textfield to "John Smith".

  my $q = new CGI;

  $q->param("name","John Smith");

  my $fif = new HTML::FillInForm;
  my $output = $fif->fill(scalarref => \$html,
			  fobject => $q);

=head1 METHODS

=over 4

=item new

Call C<new()> to create a new FillInForm object:

  $fif = new HTML::FillInForm;

=item fill

To fill in a HTML form contained in a scalar C<$html>:

  $output = $fif->fill(scalarref => \$html,
             fobject => $q);

Returns filled in HTML form contained in C<$html> with data from C<$q>.
C<$q> is required to have a C<param()> method that works like
HTML::FillInForm's C<param()>.  A good candidate would be a CGI.pm
query object. 

  $output = $fif->fill(scalarref => \$html,
             fdat => \%fdat);

Returns filled in HTML form contained in C<$html> with data from C<%fdat>.

Alternately you can use

  $output = $fif->fill(arrayref => \@array_of_lines,
             fobject => $q);

and

  $output = $fif->fill(file => 'form.tmpl',
             fobject => $q);

=back

=head1 SEE ALSO

L<HTML::Parser>

=head1 VERSION

This documenation describes HTML::FillInForm module version 0.02.

=head1 BUGS

This module has not been tested extensively.  Please submit
and bug reports to tjmather@alumni.princeton.edu.

=head1 NOTES

Requires Perl 5.005 and L<HTML::Parser> version 3.

I wrote this module because I wanted to be able to insert CGI data into HTML forms,
but without combining the HTML and Perl code.  CGI.pm and Embperl allow you so
insert CGI data into forms, but require that you mix HTML with Perl.

=head1 AUTHOR

(c) 2000 Thomas J. Mather, tjmather@alumni.princeton.com

All rights reserved. This package is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.
