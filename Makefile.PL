use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'HTML::FillInForm',
    'VERSION_FROM'	=> 'FillInForm.pm', # finds $VERSION
    'PREREQ_PM'		=> {HTML::Parser => 3}, # e.g., Module::Name => 1.1
);
