BEGIN { eval "use Mail::Box::Manager;"; 
    if ($@) { require Test::More; Test::More->import(skip_all =>
        "You don't have Mail::Box::Manager"); exit; }
}

use Test::More tests => 3;
use_ok("Mail::Thread");
my $mgr = new Mail::Box::Manager;
my $box = $mgr->open(folder => "t/testbox-2");

my $threader = new Mail::Thread($box->messages);

$threader->thread;

is($threader->rootset, 1, "We have one main threads");

my @stuff;
for ($threader->rootset) {
    dump_em($_, 0);
}

sub dump_em {
    my ($self, $level) = @_;
    push @stuff, 
    [ $level, eval { "".$self->message->head->get("Subject") }, $self->{id}
             || "[ Message not available ]" ];
    dump_em($self->next, $level) if $self->next;
    dump_em($self->child, $level+1) if $self->child;
}

is_deeply(\@stuff,
 [
          [ 0, "sort numbers", '20030101210258.63148.qmail@web20805.mail.yahoo.com' ],
          [ 1, "Re: sort numbers", 'auvpjq$ede$1@post.home.lunix' ],
          [ 1, "Re: sort numbers", 'r3i71vcul4g95orb58173qj6b8dus6pnch@4ax.com' ]
        ]);
