package HTML::FillInForm;

use integer; # no floating point math so far!
use strict; # and no funny business, either.

use Carp; # generate better errors with more context

# required for attr_encoded
use HTML::Parser 3.26;

# required for UNIVERSAL->can
require 5.005;

use vars qw($VERSION @ISA);
$VERSION = '1.05';

@ISA = qw(HTML::Parser);

sub new {
  my ($class) = @_;
  my $self = bless {}, $class;
  $self->init;
  # tell HTML::Parser not to decode attributes
  $self->attr_encoded(1);
  return $self;
}

# a few shortcuts to fill()
sub fill_file { my $self = shift; return $self->fill('file',@_); }
sub fill_arrayref { my $self = shift; return $self->fill('arrayref',@_); }
sub fill_scalarref { my $self = shift; return $self->fill('scalarref',@_); }

sub fill {
  my ($self, %option) = @_;

  my %ignore_fields;
  %ignore_fields = map { $_ => 1 } ( ref $option{'ignore_fields'} eq 'ARRAY' )
    ? @{ $option{ignore_fields} } : $option{ignore_fields} if exists( $option{ignore_fields} );
  $self->{ignore_fields} = \%ignore_fields;

  if (my $fdat = $option{fdat}){
    # Copy the structure to prevent side-effects.
    my %copy;
    while(my($key, $val) = each %$fdat) {
      next if exists $ignore_fields{$key};
      $copy{ $key } = ref $val eq 'ARRAY' ? [ @$val ] : $val;
    }
    $self->{fdat} = \%copy;
  }

  # We want the reference to these objects to go out of scope at the
  # end of the method.
  local $self->{objects} = [];
  if(my $objects = $option{fobject}){
    unless(ref($objects) eq 'ARRAY'){
      $objects = [ $objects ];
    }
    for my $object (@$objects){
      # make sure objects in 'param_object' parameter support param()
      defined($object->can('param')) or
	croak("HTML::FillInForm->fill called with fobject option, containing object of type " . ref($object) . " which lacks a param() method!");
    }

    $self->{objects} = $objects;
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
  unless(exists $self->{fdat} || $self->{objects}){
    croak("HTML::FillInForm->fillInForm() called without 'fobject' or 'fdat' parameter set");
  }

  local $self->{object_param_cache};

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
    $self->{object_param_cache} = {};
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
    my $value = exists $attr->{'name'} ? $self->_get_param($attr->{'name'}) : undef;
    # force hidden fields to have a value
    $value = '' if exists($attr->{'type'}) && $attr->{'type'} eq 'hidden' && ! exists $attr->{'value'} && ! defined $value;
    if (defined($value)){
      $value = $self->escapeHTMLStringOrList($value);
      # check for input type, noting that default type is text
      if (!exists $attr->{'type'} ||
	  $attr->{'type'} =~ /^(text|textfield|hidden|)$/i){
	$value = (shift @$value || '') if ref($value) eq 'ARRAY';
	$attr->{'value'} = $value;
      } elsif (lc $attr->{'type'} eq 'password' && $self->{fill_password}) {
	$value = (shift @$value || '') if ref($value) eq 'ARRAY';
	$attr->{'value'} = $value;
      } elsif (lc $attr->{'type'} eq 'radio'){
	$value = ($value->[0] || '') if ref($value) eq 'ARRAY';
	# value for radio boxes default to 'on', works with netscape
	$attr->{'value'} = 'on' unless exists $attr->{'value'};
	if ($attr->{'value'} eq $value){
	  $attr->{'checked'} = 'checked';
	} else {
	  delete $attr->{'checked'};
	}
      } elsif (lc $attr->{'type'} eq 'checkbox'){
	# value for checkboxes default to 'on', works with netscape
	$attr->{'value'} = 'on' unless exists $attr->{'value'};

	delete $attr->{'checked'}; # Everything is unchecked to start
        $value = [ $value ] unless ref($value) eq 'ARRAY';
	foreach my $v ( @$value ) {
	  if ( $attr->{'value'} eq $v ) {
	    $attr->{'checked'} = 'checked';
	  }
	}
#      } else {
#	warn(qq(Input field of unknown type "$attr->{type}": $origtext));
      }
    }
    $self->{output} .= "<$tagname";
    while (my ($key, $value) = each %$attr) {
      next if $key eq '/';
      $self->{output} .= sprintf qq( %s="%s"), $key, $value;
    }
    # extra space put here to work around Opera 6.01/6.02 bug
    $self->{output} .= ' /' if $attr->{'/'};
    $self->{output} .= ">";
  } elsif ($tagname eq 'option'){
    my $value = $self->_get_param($self->{selectName});

    if (defined($value)){
      $value = $self->escapeHTMLStringOrList($value);
      $value = [ $value ] unless ( ref($value) eq 'ARRAY' );
      delete $attr->{selected} if exists $attr->{selected};

      if(defined($attr->{'value'})){
        # option tag has value attr - <OPTION VALUE="foo">bar</OPTION>
	foreach my $v ( @$value ) {
	  if ( $attr->{'value'} eq $v ) {
	    $attr->{selected} = 'selected';
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
      $self->{output} .= sprintf qq( %s="%s"), $key, $value;
    }
    unless ($self->{option_no_value}){
      # we can close option tag here
      $self->{output} .= ">";
    }
  } elsif ($tagname eq 'textarea'){
    if ($attr->{'name'} and defined (my $value = $self->_get_param($attr->{'name'}))){
      $value = $self->escapeHTMLStringOrList($value);
      $value = (shift @$value || '') if ref($value) eq 'ARRAY';
      # <textarea> foobar </textarea> -> <textarea> $value </textarea>
      # we need to set outputText to 'no' so that 'foobar' won't be printed
      $self->{outputText} = 'no';
      $self->{output} .= $origtext . $value;
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

sub _get_param {
  my ($self, $param) = @_;

  return undef if $self->{ignore_fields}{$param};

  return $self->{fdat}{$param} if exists $self->{fdat}{$param};

  return $self->{object_param_cache}{$param} if exists $self->{object_param_cache}{$param};

  # traverse the list in reverse order for backwards compatibility
  # with the previous implementation.
  for my $o (reverse @{$self->{objects}}) {
    my @v = $o->param($param);

    next unless @v;

    return $self->{object_param_cache}{$param} = @v > 1 ? \@v : $v[0];
  }

  return undef;
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
	if ( $value eq $v ) {
	  $self->{output} .= ' selected="selected"';
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

sub escapeHTMLStringOrList {
  my ($self, $toencode) = @_;

  if (ref($toencode) eq 'ARRAY') {
    foreach my $elem (@$toencode) {
      $elem = $self->escapeHTML($elem);
    }
    return $toencode;
  } else {
    return $self->escapeHTML($toencode);
  }
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
  $self->{output} .= '<!' . $text . '>';
}

1;

__END__

=head1 NAME

HTML::FillInForm - Populates HTML Forms with data.

=head1 DESCRIPTION

This module automatically inserts data from a previous HTML form into the HTML input, textarea,
radio buttons, checkboxes and select tags.
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

Note CGI.pm is B<not> required - see using fdat below.  Also you can use a CGI.pm-like object such as Apache::Request.

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

As of 1.04 the object passed does not need to return all its keys with
a empty param() call.

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

To disable the filling of some fields, use the C<ignore_fields> option:

  $output = $fif->fill(scalarref => \$html,
                       fobject => $q,
                       ignore_fields => ['prev','next']);

Note that this module does not clear fields if you set the value to undef.
It will clear fields if you set the value to an empty array or an empty string.  For example:

  # this will leave the form element foo untouched
  $output = $fif->fill(scalarref => \$html,
             fdat => { foo => undef });

  # this will set clear the form element foo
  $output = $fif->fill(scalarref => \$html,
             fdat => { foo => "" });

It has been suggested to add a option to the new constructer to change the behavior
so that undef values will clear the form elements.  Patches welcome.

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

=head2 HTML::Mason

Using HTML::FillInForm from HTML::Mason is covered in the FAQ on
the masonhq.com website at
L<http://www.masonhq.com/docs/faq/#how_can_i_integrate_html_fillin>

=head1 VERSION

This documentation describes HTML::FillInForm module version 1.04.

=head1 SECURITY

Note that you might want to think about caching issues if you have password
fields on your page.  There is a discussion of this issue at

http://www.perlmonks.org/index.pl?node_id=70482

In summary, some browsers will cache the output of CGI scripts, and you
can control this by setting the Expires header.  For example, use
C<-expires> in L<CGI.pm> or set C<browser_cache> to I<no> in 
Config.xml file of L<Apache::PageKit>.

=head1 TRANSLATION

Kato Atsushi has translated these docs into Japanese, available from

http://perldoc.jp

=head1 BUGS

Please submit any bug reports to tjmather@maxmind.com.

=head1 NOTES

Requires Perl 5.005 and L<HTML::Parser> version 3.26.

I wrote this module because I wanted to be able to insert CGI data
into HTML forms,
but without combining the HTML and Perl code.  CGI.pm and Embperl allow you so
insert CGI data into forms, but require that you mix HTML with Perl.

There is a nice review of the module available here:
http://www.perlmonks.org/index.pl?node_id=274534

=head1 AUTHOR

(c) 2004 TJ Mather, Maxmind LLC, tjmather@maxmind.com

All rights reserved. This package is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

Paid support is available from directly from the author of this package.
Please see L<http://www.maxmind.com/app/opensourceservices> for more details.

=head1 SEE ALSO

L<HTML::Parser>, L<Data::FormValidator>, L<HTML::Template>, L<Apache::PageKit>

=head1 CREDITS

Fixes, Bug Reports, Docs have been generously provided by:

  Tatsuhiko Miyagawa
  Boris Zentner
  Dave Rolsky
  Patrick Michael Kane
  Ade Olonoh
  Tom Lancaster
  Martin H Sluka
  Mark Stosberg
  Jonathan Swartz
  Trevor Schellhorn
  Jim Miner
  Paul Lindner
  Maurice Aubrey
  Andrew Creer
  Joseph Yanni
  Philip Mak
  Jost Krieger
  Gabriel Burka
  Bill Moseley
  James Tolley
  Dan Kubb

Thanks!
