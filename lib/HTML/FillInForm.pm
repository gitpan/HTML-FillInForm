package HTML::FillInForm;

use integer; # no floating point math so far!
use strict; # and no funny business, either.

use Carp; # generate better errors with more context

use HTML::Parser 3.08;

# required for UNIVERSAL->can
require 5.005;

use vars qw($VERSION @ISA);
$VERSION = '0.27';
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

  if (my $fdat = $option{fdat}){
    # Copy the structure to prevent side-effects.
    # Notice that we also convert all values to array references.
    my %copy;
    while(my($key, $val) = each %$fdat) {
      $copy{ $key } = [ ref $val eq 'ARRAY' ? @$val : $val ];
    }
    $self->{fdat} = \%copy;
  }
  if(my $objects = $option{fobject}){
    unless(ref($objects) eq 'ARRAY'){
      $objects = [ $objects ];
    }
    $self->{fdat} = {} unless exists $self->{fdat};
    for my $object (@$objects){
      # make sure objects in 'param_object' parameter support param()
      defined($object->can('param')) or
	croak("HTML::FillInForm->fill called with fobject option, containing object of type " . ref($object) . " which lacks a param() method!");
      foreach my $k ($object->param()){
	# we expect param to return an array if there are multiple values
	my @v = $object->param($k);
	$self->{fdat}->{$k} = \@v;
      }
    }
  }
  if (my $target = $option{target}){
    $self->{'target'} = $target;
  }

  if (defined($option{fill_password})){
    $self->{fill_password} = $option{fill_password};
  } else {
    $self->{fill_password} = 1;
  }

  # make sure method has data to fill in HTML form with!
  unless(exists $self->{fdat}){
    croak("HTML::FillInForm->fillInForm() called without 'fobject' or 'fdat' parameter set");
  }

  if(my $file = $option{file}){
    $self->parse_file($file);
  } elsif (my $scalarref = $option{scalarref}){
    $self->parse($$scalarref);
  } elsif (my $arrayref = $option{arrayref}){
    for (@$arrayref){
      $self->parse($_);
    }
  }
  return delete $self->{output};
}

# handles opening HTML tags such as <input ...>
sub start {
  my ($self, $tagname, $attr, $attrseq, $origtext) = @_;

  # set the current form
  if ($tagname eq 'form') {
    if (exists $attr->{'name'}) {
      $self->{'current_form'} = $attr->{'name'};
    } else {
      # in case of previous one without </FORM>
      delete $self->{'current_form'};
    }
  }

  # This form is not my target.
  if (exists $self->{'target'} &&
      (! exists $self->{'current_form'} ||
       $self->{'current_form'} ne $self->{'target'})) {
    $self->{'output'} .= $origtext;
    return;
  }
  
  # HTML::Parser converts tagname to lowercase, so we don't need /i
  if ($self->{option_no_value}) {
    $self->{output} .= '>';
    delete $self->{option_no_value};
  }
  if ($tagname eq 'input'){
    my $value = exists $attr->{'name'} ? $self->{fdat}->{$attr->{'name'}} : undef;
    # force hidden fields to have a value
    $value = [] if exists($attr->{'type'}) && $attr->{'type'} eq 'hidden' && ! exists $attr->{'value'} && ! defined $value;
    if (defined($value)){
      # check for input type, noting that default type is text
      if (!exists $attr->{'type'} ||
	  $attr->{'type'} =~ /^(text|textfield|hidden|)$/i){
	$value = (shift @$value || '');
	$attr->{'value'} = $value;
      } elsif (lc $attr->{'type'} eq 'password' && $self->{fill_password}) {
	$value = shift @$value || '';
	$attr->{'value'} = $value;
      } elsif (lc $attr->{'type'} eq 'radio'){
        $value = $value->[0];
	# value for radio boxes default to 'on', works with netscape
	$attr->{'value'} = 'on' unless exists $attr->{'value'};
	if ($attr->{'value'} eq $value){
	  $attr->{'checked'} = '__BOOLEAN__';
	} else {
	  delete $attr->{'checked'};
	}
      } elsif (lc $attr->{'type'} eq 'checkbox'){
	# value for checkboxes default to 'on', works with netscape
	$attr->{'value'} = 'on' unless exists $attr->{'value'};

	delete $attr->{'checked'}; # Everything is unchecked to start

	foreach my $v ( @$value ) {
	  if ( $attr->{'value'} eq $v ) {
	    $attr->{'checked'} = '__BOOLEAN__';
	  }
	}
#      } else {
#	warn(qq(Input field of unknown type "$attr->{type}": $origtext));
      }
    }
    $self->{output} .= "<$tagname";
    while (my ($key, $value) = each %$attr) {
      if($value eq '__BOOLEAN__'){
        next if $key eq '/';
	# boolean attribute
	$self->{output} .= " $key";
      } else {
	$self->{output} .= sprintf qq( %s="%s"), $key, $self->escapeHTML($value);
      }
    }
    $self->{output} .= '/' if $attr->{'/'};
    $self->{output} .= ">";
  } elsif ($tagname eq 'option'){
    my $value = $self->{fdat}->{$self->{selectName}};
    if (defined($value)){
      delete $attr->{selected} if exists $attr->{selected};

      if(defined($attr->{'value'})){
        # option tag has value attr - <OPTION VALUE="foo">bar</OPTION>
	foreach my $v ( @$value ) {
	  if ( $attr->{'value'} eq $v ) {
	    $attr->{selected} = '__BOOLEAN__';
	  }
        }
      } else {
        # option tag has no value attr - <OPTION>bar</OPTION>
	# save for processing under text handler
	$self->{option_no_value} = $value;
      }
    }
    $self->{output} .= "<$tagname";
    while (my ($key, $value) = each %$attr) {
      if($value eq '__BOOLEAN__'){
        next if $key eq '/';
	# boolean attribute
	$self->{output} .= " $key";
      } else {
	$self->{output} .= sprintf qq( %s="%s"), $key, $self->escapeHTML($value);
      }
    }
    unless ($self->{option_no_value}){
      # we can close option tag here
      $self->{output} .= ">";
    }
  } elsif ($tagname eq 'textarea'){
    if (defined(my $value = $self->{fdat}->{$attr->{'name'}})){
      $value = (shift @$value || '');
      # <textarea> foobar </textarea> -> <textarea> $value </textarea>
      # we need to set outputText to 'no' so that 'foobar' won't be printed
      $self->{outputText} = 'no';
      $self->{output} .= $origtext . $self->escapeHTML($value);
    } else {
      $self->{output} .= $origtext;
    }
  } elsif ($tagname eq 'select'){
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
  unless(exists $self->{outputText} && $self->{outputText} eq 'no'){
    if(exists $self->{option_no_value}){
      # dealing with option tag with no value - <OPTION>bar</OPTION>
      my $values = $self->{option_no_value};
      my $value = $origtext;
      $value =~ s/^\s+//;
      $value =~ s/\s+$//;
      foreach my $v ( @$values ) {
	if ( $value eq $self->escapeHTML($v) ) {
	  $self->{output} .= " selected";
        }
      }
      # close <OPTION> tag
      $self->{output} .= ">$origtext";
      delete $self->{option_no_value};
    } else {
      $self->{output} .= $origtext;
    }
  }
}

# handles closing HTML tags such as </textarea>
sub end {
  my ($self, $tagname, $origtext) = @_;
  if ($self->{option_no_value}) {
    $self->{output} .= '>';
    delete $self->{option_no_value};
  }
  if($tagname eq 'select'){
    delete $self->{selectName};
  } elsif ($tagname eq 'textarea'){
    delete $self->{outputText};
  } elsif ($tagname eq 'form') {
    delete $self->{'current_form'};
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

sub comment {
  my ( $self, $text ) = @_;
  $self->{output} .= '<!--' . $text . '-->';
}

sub process {
  my ( $self, $token0, $text ) = @_;
  $self->{output} .= $text;
}

sub declaration {
  my ( $self, $text ) = @_;
  $self->{output} .= '<' . $text . '>';
}

1;

__END__

=head1 NAME

HTML::FillInForm - Populates HTML Forms with CGI data.

=head1 DESCRIPTION

This module automatically inserts data from a previous HTML form into the HTML input, textarea and select tags.
It is a subclass of L<HTML::Parser> and uses it to parse the HTML and insert the values into the form tags.

One useful application is after a user submits an HTML form without filling out a
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
CGI's C<param()>.

  $output = $fif->fill(scalarref => \$html,
             fobject => [$q1, $q2]);

Note that you can pass multiple objects as an array reference.

  $output = $fif->fill(scalarref => \$html,
             fdat => \%fdat);

Returns filled in HTML form contained in C<$html> with data from C<%fdat>.
To pass multiple values using C<%fdat> use an array reference.

Alternately you can use

  $output = $fif->fill(arrayref => \@array_of_lines,
             fobject => $q);

and

  $output = $fif->fill(file => 'form.tmpl',
             fobject => $q);

Suppose you have multiple forms in a html and among them there is only
one form you want to fill in, specify target.

  $output = $fif->fill(scalarref => \$html,
                       fobject => $q,
                       target => 'form1');

This will fill in only the form inside

  <FORM name="form1"> ... </FORM>

Note that this method fills in password fields by default.  To disable, pass

  fill_password => 0

=back

=head1 CALLING FROM OTHER MODULES

=head2 Apache::PageKit

To use HTML::FillInForm in L<Apache::PageKit> is easy.   It is
automatically called for any page that includes a <form> tag.
It can be turned on or off by using the C<fill_in_form> configuration
option.

=head2 Apache::ASP v2.09 and above

HTML::FillInForm is now integrated with Apache::ASP.  To activate, use

  PerlSetVar FormFill 1
  $Response->{FormFill} = 1

=head1 VERSION

This documentation describes HTML::FillInForm module version 0.27.

=head1 SECURITY

Note that you might want to think about caching issues if you have password
fields on your page.  There is a discussion of this issue at

http://www.perlmonks.org/index.pl?node_id=70482

In summary, some browsers will cache the output of CGI scripts, and you
can control this by setting the Expires header.  For example, use
C<-expires> in L<CGI.pm> or set C<browser_cache> to I<no> in 
Config.xml file of L<Apache::PageKit>.

=head1 BUGS

Please submit any bug reports to tjmather@tjmather.com.

=head1 NOTES

Requires Perl 5.005 and L<HTML::Parser> version 3.08.

I wrote this module because I wanted to be able to insert CGI data
into HTML forms,
but without combining the HTML and Perl code.  CGI.pm and Embperl allow you so
insert CGI data into forms, but require that you mix HTML with Perl.

=head1 AUTHOR

(c) 2002 Thomas J. Mather, tjmather@tjmather.com

All rights reserved. This package is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<HTML::Parser>, L<Data::FormValidator>, L<HTML::Template>, L<Apache::PageKit>

=head1 CREDITS

Fixes, Bug Reports, Docs have been generously provided by:

  Tatsuhiko Miyagawa
  Boris Zentner
  Patrick Michael Kane
  Ade Olonoh
  Tom Lancaster
  Martin H Sluka
  Mark Stosberg
  Trevor Schellhorn
  Jim Miner
  Paul Lindner
  Maurice Aubrey
  Andrew Creer
  Joseph Yanni
  Philip Mak
  Jost Krieger

Thanks!
