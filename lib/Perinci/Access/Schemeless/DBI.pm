package Perinci::Access::Schemeless::DBI;

use 5.010001;
use strict;
use warnings;
use experimental 'smartmatch';

use JSON;
my $json = JSON->new->allow_nonref;

use parent qw(Perinci::Access::Schemeless);

our $VERSION = '0.01'; # VERSION

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    # check required attributes
    die "Please specify required attribute 'dbh'" unless $self->{dbh};

    $self;
}

sub get_meta {
    my ($self, $req) = @_;

    my $leaf = $req->{-uri_leaf};

    if (length $leaf) {
        my ($meta) = $self->{dbh}->selectrow_array(
            "SELECT metadata FROM function WHERE module=? AND name=?", {},
            $req->{-perl_package}, $leaf);
        if ($meta) {
            $req->{-meta} = $json->decode($meta);
        } else {
            return [400, "No metadata found in database"];
        }
    } else {
        # XXP check in database, if exists return if not return {v=>1.1}
        my ($meta) = $self->{dbh}->selectrow_array(
            "SELECT metadata FROM module WHERE name=?", {},
            $req->{-perl_package});
        if ($meta) {
            $req->{-meta} = $json->decode($meta);
        } else {
            $req->{-meta} = {v=>1.1}; # empty metadata for /
        }
    }
    return;
}

sub action_list {
    my ($self, $req) = @_;
    my $detail = $req->{detail};
    my $f_type = $req->{type} || "";

    my @res;

    # XXX duplicated code with parent class
    my $filter_path = sub {
        my $path = shift;
        if (defined($self->{allow_paths}) &&
                !__match_paths2($path, $self->{allow_paths})) {
            return 0;
        }
        if (defined($self->{deny_paths}) &&
                __match_paths2($path, $self->{deny_paths})) {
            return 0;
        }
        1;
    };

    my $sth;

    # get submodules
    unless ($f_type && $f_type ne 'package') {
        if (length $req->{-perl_package}) {
            $sth = $self->{dbh}->prepare(
                "SELECT name FROM module WHERE name LIKE ? ORDER BY name");
            $sth->execute("$req->{-perl_package}\::%");
        } else {
            $sth = $self->{dbh}->prepare(
                "SELECT name FROM module ORDER BY name");
            $sth->execute;
        }
        # XXX produce intermediate prefixes (e.g. user requests 'foo::bar' and
        # db lists 'foo::bar::baz::quux', then we must also produce
        # 'foo::bar::baz'
        while (my $r = $sth->fetchrow_hashref) {
            my $m = $r->{name}; $m =~ s!::!/!g;
            if ($detail) {
                push @res, {uri=>"/$m/", type=>"package"};
            } else {
                push @res, "/$m/";
            }
        }
    }

    # get all entities from this module. XXX currently only functions
    my $dir = $req->{-uri_dir};
    $sth = $self->{dbh}->prepare(
        "SELECT name FROM function WHERE module=? ORDER BY name");
    $sth->execute($req->{-perl_package});
    while (my $r = $sth->fetchrow_hashref) {
        my $e = $r->{name};
        my $path = "$dir/$e";
        next unless $filter_path->($path);
        my $t = $e =~ /^[%\@\$]/ ? 'variable' : 'function';
        next if $f_type && $f_type ne $t;
        if ($detail) {
            push @res, {
                #v=>1.1,
                uri=>$e, type=>$t,
            };
        } else {
            push @res, $e;
        }
    }

    [200, "OK (list action)", \@res];
}

1;
# ABSTRACT: Subclass of Perinci::Access::Schemeless which gets lists of entities (and metadata) from DBI database

__END__

=pod

=encoding UTF-8

=head1 NAME

Perinci::Access::Schemeless::DBI - Subclass of Perinci::Access::Schemeless which gets lists of entities (and metadata) from DBI database

=head1 VERSION

version 0.01

=head1 DESCRIPTION

This subclass of Perinci::Access::Schemeless gets lists of code entities
(currently only packages and functions) from a DBI database (instead of from
listing Perl packages on the filesystem). It can also retrieve L<Rinci> metadata
from said database (instead of from C<%SPEC> package variables).

Currently, you must have a table containing list of packages named C<module>
with columns C<name> (module name), C<metadata> (Rinci metadata, encoded in
JSON); and a table containing list of functions named C<function> with columns
C<module> (module name), C<name> (function name), and C<metadata> (normalized
Rinci metadata, encoded in JSON). Table and column names will be configurable in
the future. An example of the table's contents:

 name      metadata
 ----      ---------
 Foo::Bar  (null)
 Foo::Baz  {"v":"1.1"}

 module    name         metadata
 ------    ----         --------
 Foo::Bar  func1        {"v":"1.1","summary":"function 1","args":{}}
 Foo::Bar  func2        {"v":"1.1","summary":"function 2","args":{}}
 Foo::Baz  func3        {"v":"1.1","summary":"function 3","args":{"a":{"schema":["int",{},{}]}}}

=for Pod::Coverage ^(.+)$

=head1 HOW IT WORKS

The subclass overrides get_meta() and action_list().

=head1 METHODS

=head1 new(%args) => OBJ

Aside from its parent class, this class recognizes these attributes:

=over

=item * dbh => OBJ (required)

DBI database handle.

=back

=head1 FAQ

=head2 Rationale for this module?

If you have a large number of packages and functions, you might want to avoid
reading Perl modules on the filesystem.

=head1 SEE ALSO

L<Riap>, L<Rinci>

=head1 HOMEPAGE

Please visit the project's homepage at L<https://metacpan.org/release/Perinci-Access-Schemeless-DBI>.

=head1 SOURCE

Source repository is at L<https://github.com/sharyanto/perl-Perinci-Access-Schemeless-DBI>.

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website L<https://rt.cpan.org/Public/Dist/Display.html?Name=Perinci-Access-Schemeless-DBI>

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
