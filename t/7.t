BEGIN { eval "use Mail::Box::Manager;"; 
    if ($@) { require Test::More; Test::More->import(skip_all =>
        "You don't have Mail::Box::Manager"); exit; }
}

use Test::More tests => 2;
use_ok("Mail::Thread");
my $mgr = new Mail::Box::Manager;
my $box = $mgr->open(folder => "t/testbox-7");

my $threader = new Mail::Thread($box->messages);
$threader->thread;

is($threader->rootset, 1, "We have one main thread");

my @stuff;
for ($threader->rootset) {
    dump_em($_, 0);
}

sub dump_em {
    my ($self, $level) = @_;
    if ($self->next and ref($self->next) !~ /Container/) {
        use Data::Dumper; die Dumper $self;
    }
    push @stuff, 
    [ $level, eval { "".$self->message->head->get("Subject") }
             || "[ Message not available ]" ];
    dump_em($self->next, $level) if $self->next;
    dump_em($self->child, $level+1) if $self->child;
}

