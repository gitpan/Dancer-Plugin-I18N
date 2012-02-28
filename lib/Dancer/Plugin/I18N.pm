package Dancer::Plugin::I18N;

use strict;
use warnings;

use Dancer::Plugin;
use Dancer::Config;
use Dancer ':syntax';

use I18N::LangTags;
use I18N::LangTags::Detect;
use I18N::LangTags::List;

use Locale::Maketext::Simple;
#require Locale::Maketext::Simple;

our $VERSION = '0.20';
#our %options = ( Export => '_loc', Decode => 1 );
#our %options = ( Decode => 1, Encoding => 'utf-8' );
our %options = ( Decode => 1 );

# Handler of struct
my $handle = undef;

# Own subs definition
our @array_subs = ();
{
	my $settings = plugin_setting(); 
	my $n = $settings->{func};
	if (!ref($n) && length($n))	{
		register $n => sub { _localize(@_); };
		push(@array_subs, $n);
	} elsif (ref($n) eq "ARRAY")	{
		foreach my $k (@$n)	{
			register $k => sub { _localize(@_); };
			push(@array_subs, $k);
		}
	} 
}

# Hook definitions
add_hook(
    before => sub {
		_setup_i18n();
    }
);

add_hook(
    before_template => sub {
        my $tokens = shift;
        $tokens->{l}         = sub { localize(@_) };
        $tokens->{localize}  = sub { localize(@_) };
        $tokens->{language}  = sub { language(@_) };
        $tokens->{language_tag}  = sub { language_tag(@_) };
        $tokens->{languages} = sub { languages(@_) };
        $tokens->{installed_languages} = sub { installed_languages(@_) };

		foreach my $k (@{Dancer::Plugin::I18N::array_subs})	{
			$tokens->{$k} = sub { localize(@_) };		
		}
    },
);

=head1 NAME

Dancer::Plugin::I18N - Intenationalization for Dancer

=head1 SYNOPSIS

   # MyApp/I18N/de.po
   msgid "Hello Dancer"
   msgstr "Hallo Tänzerin"
   
   # MyApp/I18N/i_default.po
   msgid "messages.hello.dancer"
   msgstr "Hello Dancer - fallback translation"
   
   # MyApp/I18N/fr.pm
   package myapp::I18N::fr;
   use base 'myapp::I18N';
   our %Lexicon = ( hello => 'bonjour' );
   1;

   package myapp;
   use Dancer;
   use Dancer::Plugin::I18N;
   get '/' => sub {
        my $lang = languages ;
        print @$lang . "\n";
        languages( ['de'] );
        print STDERR localize('Hello Dancer');

        template 'index' 
    };

    # index.tt
    hello in <% languages %> => <% l('hello') %>
    # or
    <% languages('fr') %>This is an <% l('hello') %>
    # or
    <% l('Hello Dancer') %>
    <% l('Hello [_1]', 'Dancer') %>
    <[% l('lalala[_1]lalala[_2]', ['test', 'foo']) %>
    <% l('messages.hello.dancer') %>
    # or for big texts
    <% IF language_tag('fr') %>
    ...
    <% ELSE %>
    ...
    <% ENDIF %>


=head1 DESCRIPTION

Supports mo/po files and Maketext classes under your application's I18N namespace.

Dancer::Plugin::I18N add L<Locale::Maketext::Simple> to your L<Dancer> application

=cut

sub _setup_i18n { 

	return if (defined($handle) && ref($handle) eq "HASH");

	my $settings = plugin_setting(); 

	my $lang_path = $settings->{directory} || path(setting('appdir'), 'I18N');

    my $user_opts = $settings->{ maketext_options } || {};
    local %options = (%options, Path => $lang_path, %$user_opts );

	#Locale::Maketext::Simple->import( %options );
	my $self = __PACKAGE__;
    eval <<"";
        package $self;
        Locale::Maketext::Simple->import( \%Dancer\::Plugin\::I18N\::options );

    if ($@) {
        error("Couldn't initialize i18n", "$@");
    }
    else {
        debug("Initialized i18n");
    }

=head1 CONFIGURATION

You can override any parameter sent to L<Locale::Maketext::Simple> by specifying
a C<maketext_options> hashref to the C<Plugin::I18N> in you Dancer application
config file section. For example, the following configuration will override 
the C<Decode> parameter which normally defaults to C<1>:

    plugins:
       I18N:
          directory: I18N
          lang_default: en
          maketext_options:
               Decode: 0

All languages fallback to MyApp::I18N which is mapped onto the i-default
language tag or change this via options 'language_default'. 
If you use arbitrary message keys, use i_default.po to translate
into English, otherwise the message key itself is returned.

Standart directory is in C<I18N>. In this directory are stored every lang files (*.pm|po|mo).

You can defined own function for call locale via settings name C<func>.

    plugins:
       I18N:
          func: "N_"

Or defined as array:

    plugins:
       I18N:
          func: ["N_", "_"]

Now you can call this function in template or in libs.

    # index.tt
    hello in <% languages %> => <% N_('hello') %>

=cut

	# We re-read the list of files in $lang_path
	# Originally tried to detect via namespaces, but this lists the currently set LANG envvar, which may not
	# be a supported language. Also misses out .pm files
	# Is acceptable to re-read this directory once on setup
	my $languages_list = {};
	if (opendir my $langdir, $lang_path) {
		foreach my $entry (readdir $langdir) {
			next unless $entry =~ m/\A (\w+)\.(?:pm|po|mo) \z/xms;
			my $langtag = $1;
			next if $langtag eq "i_default";
			my $language_tag = $langtag;
			#my $language_tag = "$class\::I18N"->get_handle( $langtag )->language_tag;
			# Did use the get_handle, but that caused problems because en became "Default (Fallthru) Language"
			# Just do a simple convert instead
			$language_tag =~ s/_/-/g;
			$languages_list->{ $langtag } = I18N::LangTags::List::name( $language_tag );
		}
		closedir $langdir;
	}

	$handle = {};
	$handle->{installed_languages} = $languages_list;
	
	# Setting language
	my $request = request;
	my @languages = ();
    push @languages,
			I18N::LangTags::implicate_supers(
				I18N::LangTags::Detect->http_accept_langs(
					scalar $request->accept_language
				)
			);
	push (@languages, $settings->{lang_default} || 'i-default');
	$handle->{languages} = \@languages;
}

=head1 METHODS

=head2 languages

Contains languages.

   languages(['de_DE']);
   my $lang = languages;
   print join '', @$lang;

=head3 1. Putting new language as first in finded

   languages('de_DE'); 

=head3 2. Erase all and putting new languages as in arrayref

   languages(['de_DE',....,'en']); 

=head3 3. Return putted languages

   languages();

=cut
register languages		=> sub { 
    my $lang = shift;

	_setup_i18n();
	return if (!$handle);

    if ($lang) {
		if (ref($lang) eq "ARRAY")	{
			$handle->{languages} = $lang;
		} else	{
			for (my $i = 0; $i < scalar(@{$handle->{languages}}); $i ++)	{
				if ($handle->{languages}->[$i] eq $lang)	{
					splice(@{$handle->{languages}},$i,1);
					last;
				}
			}
			unshift(@{$handle->{languages}}, $lang);
		}

		#no strict 'refs';
		#my $c = __PACKAGE__;
		#&{ ref($c) . '::_loc_lang' }( @{ $handle->{languages} } );
    	loc_lang( @{ $handle->{languages} } );
	}

	return $handle->{languages};
};

=head2 language

return selected locale in your locales list or check if given locale is used(same as language_tag).

=cut

register language		=> sub { 
	my $lang_test = shift;

	return language_tag($lang_test) if (defined($lang_test));

	my $c = __PACKAGE__;
	my $class = ref $c || $c;
    my $lang = $handle ? "$class\::I18N"->get_handle( @{ $handle->{languages} } ) : "";
    $lang =~ s/.*:://;

    return $lang;
};

=head2 language_tag

return language tag for current locale. The most notable difference from this
method in comparison to C<language()> is typically that languages and regions
are joined with a dash and not an underscore.

    language(); # en_us
    language_tag(); # en-us

=head3 1. Returning selected locale 

	print language_tag();

=head3 2. Test if given locale used

	if (language_tag('en'))	{}

=cut

register language_tag	=> sub { 
	my $lang_test = shift;

	my $c = __PACKAGE__;
	my $class = ref $c || $c;
    my $ret = $handle ? "$class\::I18N"->get_handle( @{ $handle->{languages} } )->language_tag : "";

	if (defined($lang_test))	{
		return 1 if ($ret eq $lang_test || $ret =~ /^$lang_test/);
		return 0;
	}

	return $ret;
};

=head2 installed_languages

Returns a hash of { langtag => "descriptive name for language" } based on language files
in your application's I18N directory. The descriptive name is based on I18N::LangTags::List information.
If the descriptive name is not available, will be undef.

=head3 1. Returning hashref installed language files

	my $l = installed_language();

=head3 2. Test if given locale is installed in hashref

	my $t = installed_language('en');
	

=cut

register installed_languages	=> sub { 
	if (defined($handle))	{
		if (defined($_[0]))	{
			return 1 if($handle->{installed_languages} && $handle->{installed_languages}->{$_[0]});
			return 0;
		}
		return $handle->{installed_languages};
	}
};

=head2 localize | l

Localize text.

    print localize( 'Welcome to Dancer, [_1]', 'sri' );

is same as

    print l( 'Welcome to Dancer, [_1]', 'sri' );

or in template
  
    <% l('Welcome to Dancer, [_1]', 'sri' ) %>

=cut

register localize		=> sub { _localize(@_); };
register l				=> sub { _localize(@_); };

sub _localize {
	_setup_i18n();
	return '' if (scalar(@_) == 0);
	return join '', @_ if (!defined($handle));
	
    return loc( $_[0], @{ $_[1] } ) if ( ref $_[1] eq 'ARRAY' );
    return loc(@_);
	#no strict 'refs';
	#my $c = __PACKAGE__;
	#return &{ ref($c) . '::_loc' }( $_[0], @{ $_[1] } ) if ( ref $_[1] eq 'ARRAY' );
	#return &{ ref($c) . '::_loc' }(@_);
}

=head1 OUTLINE

    $ dancer -a MyAPP
    $ cd MyAPP
    $ mkdir I18N
    $ xgettext.pl --output=I18N/messages.pot --directory=lib/
    $ ls I18N/
    messages.pot

    $ msginit --input=messages.pot --output=sv.po --locale=sv.utf8
    Created I18N/sv.po.

    $ vim I18N/sv.po

    "Content-Type: text/plain; charset=utf-8\n"

    #: lib/MyApp.pm:50
    msgid "Guest"
    msgstr "Gäst"
    
    #. ($name)
    #: lib/MyApp.pm:54
    msgid "Welcome %1!"
    msgstr "Välkommen %1!"

    $ xgettext.pl --output=I18N/messages.pot --directory=view/
    $ msgmerge --update I18N/sv.po I18N/messages.pot
    . done.

    # compile message catalog to binary format
    $ msgfmt --output-file=I18N/sv.mo I18N/sv.po

=head1 SEE ALSO

L<Dancer>

L<Catalyst::Plugin::I18N>

=head1 AUTHOR

franck cuny E<lt>franck@lumberjaph.netE<gt>

Igor Bujna E<lt>igor.bujna@post.czE<gt>

=head1 ACKNOWLEDGEMENTS

Thanks for authors of L<Catalyst::Plugin::I18N> with idea how make it.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

register_plugin;

1;
