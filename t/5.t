BEGIN { eval "use Mail::Box::Manager;"; 
    if ($@) { require Test::More; Test::More->import(skip_all =>
        "You don't have Mail::Box::Manager"); exit; }
}

use Test::More tests => 2;
use_ok("Mail::Thread");
package My::Thread;
@ISA = qw(Mail::Thread);
sub _container_class { 'My::Thread::Container' }

sub _finish { }

package My::Thread::Container;
@ISA = qw(Mail::Thread::Container);

our %stuff;

sub new {
    my ($class, $id) = @_;
    if (!$stuff{$id})  { $stuff{$id} = $class->SUPER::new($id); }
    return $stuff{$id};

}

package main;

my $mgr = new Mail::Box::Manager;
my $box = $mgr->open(folder => "t/testbox-5");

for ($box->messages) {
    my $threader = new My::Thread($_);

    $threader->thread;
}

ok(2, "Completes successfully...");
