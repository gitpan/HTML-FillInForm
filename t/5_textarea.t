
use strict;

$^W = 1;

print "1..2\n";

use HTML::FillInForm;

print "ok 1\n";

my $hidden_form_in = qq{<TEXTAREA NAME="foo">blah</TEXTAREA>};

my %fdat = (foo => 'bar');

my $fif = new HTML::FillInForm;
my $output = $fif->fill(scalarref => \$hidden_form_in,
			fdat => \%fdat);
if ($output eq '<TEXTAREA NAME="foo">bar</TEXTAREA>'){
	print "ok 2\n";
} else {
	print "Got unexpected out for $hidden_form_in:\n$output\n";
	print "not ok 2\n";
}
