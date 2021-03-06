package Dist::Zilla::Plugin::MinimumPrereqs;

# VERSION
# ABSTRACT: Adjust blank prereqs to use the lowest version available

use sanity;
use Moose;

use List::AllUtils qw(min max part);
use version 0.77;

with 'Dist::Zilla::Role::PrereqSource';
with 'Dist::Zilla::Role::MetaCPANInterfacer';

has minimum_year => (
   is      => 'ro',
   isa     => 'Int',
   default => 2008,
);

sub register_prereqs {
   my ($self) = @_;
   my $zilla   = $self->zilla;
   my $prereqs = $zilla->prereqs->cpan_meta_prereqs;

   # Find the lowest required dependencies
   $self->log("Searching for minimum dependency versions");
   
   foreach my $phase (qw(configure runtime build test)) {
      $self->logger->set_prefix("{Phase '$phase'} ");
      foreach my $relationship (qw(requires recommends suggests)) {
         my $req = $prereqs->requirements_for($phase, $relationship);
         
         foreach my $module ( sort ($req->required_modules) ) {
            next if $module eq 'perl';  # obvious

            $req->requirements_for_module($module) and next;  # bounce if there is a version string
            my $minver = $self->_mcpan_module_minrelease($module);
            next unless $minver;
            
            $self->log_debug(['Found minimum dep version for Module %s %s', $module, $minver]);
            $req->add_minimum( $module => $minver );
         }
      }
   }
   $self->logger->clear_prefix;
}

sub _mcpan_module_minrelease {
   my ($self, $module, $try_harder) = @_;
   my $year = $self->minimum_year;
  
   my %search_params = (
      sort   => 'date',
      fields => 'date,distribution,module.version,module.name',
      size   => $try_harder ? 20 : 1,   
   );
  
   ### XXX: This should be replaced with a ->file() method when those
   ### two pull requests of mine are put into CPAN...
   $search_params{q} = join(' AND ', 'module.name:"'.$module.'"', 'maturity:released', 'module.authorized:true', "date:[$year TO 2099]");
   $self->log_debug("Checking module $module via MetaCPAN");
   #$self->log_debug('   [q='.$search_params{q}.']');
   my $details = $self->mcpan->fetch( "file/_search", %search_params );
   unless ($details && $details->{hits}{total}) {
      # it's possible that the minimum year is too high for this module
      $search_params{q} = join(' AND ', 'module.name:"'.$module.'"', 'maturity:released', 'module.authorized:true');
      $search_params{sort} = 'date:desc';
      $details = $self->mcpan->fetch( "file/_search", %search_params );      
      
      unless ($details && $details->{hits}{total}) {
         $self->log("??? MetaCPAN can't even find a good version for $module!");
         return undef;
      }
   }

   # Sometimes, MetaCPAN just gets highly confused...
   my @hits = @{ $details->{hits}{hits} };
   my $hit;
   my $is_bad = 1;
   do {
      $hit = shift @hits;
      # (ie: we shouldn't have multiples of modules or versions, and sort should actually have a value)
      $is_bad = !$hit->{sort}[0] || ref $hit->{fields}{'module.name'} || ref $hit->{fields}{'module.version'};
   } while ($is_bad and @hits);
   
   if ($is_bad) {
      if ($try_harder) {
         $self->log("??? MetaCPAN is highly confused about $module!");
         return undef;
      }
      $self->log_debug("   MetaCPAN got confused; trying harder...");
      return $self->_mcpan_module_minrelease($module, 1)
   }
   
   return $hit->{fields}{'module.version'};
}

__PACKAGE__->meta->make_immutable;
42;

__END__

=begin wikidoc

= SYNOPSIS
 
   ; ...other Prereq plugins...
   [MinimumPrereqs]
   minimum_year = 2008  ; default

= DESCRIPTION
 
This plugin will scan for any "blank" pre-requirement (ie: {Module => 0}), search MetaCPAN
for the lowest version that was released at least within {minimum_year}, and fix the prereq
to contain that mimimum version.

== Why bother?

Put your money where your mouth is.  If you say that you can support *any version*, like
[Moose v0.01|http://search.cpan.org/~stevan/Moose-0.01/], then actually commit to it.

What's that?  You don't actually think it'll work on the very first version of Moose?  Then
at least commit to something that was released in year 20XX.

== Why not just use LatestPrereqs?

Some users prefer to download as little from CPAN as they need to, and keep their Perl
requirements in the same place as their OS requirements.  For example, Debian's apt system
has thousands of Perl modules, with all of the proper requirements and dependencies, thanks
to the [Debian Perl Group|http://pkg-perl.alioth.debian.org/]'s work to translate those
Perl modules to Debian packages.  This keeps OS dependencies clean and makes upgrades
seemless.

By maintaining accurate minimum prereqs, you can find a good happy medium between making sure
your module works for the right version ranges, and not promoting overly restrictive version
requirements.

= OPTIONS

== minimum_year

This is the lowest release year it will accept to add as a minimum requirement.  For example,
if you have a Moose requirement as {Moose => 0}, under the default year of 2008, it will change
this to {Moose => 0.34}, which was released in January 21, 2008.

= SEE ALSO

* [@Prereqs|Dist::Zilla::PluginBundle::Prereqs]
* Other Dist::Zilla Prereq plugins: [Prereqs|Dist::Zilla::Plugin::Prereqs], [AutoPrereqs|Dist::Zilla::Plugin::AutoPrereqs],
[LatestPrereqs|Dist::Zilla::Plugin::LatestPrereqs]
* The [Dist::Zilla::Plugin::TravisYML|TravisYML] plugin and MVDT (Minimum Dependency Version Testing)

=end wikidoc
