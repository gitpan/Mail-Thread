BEGIN { eval "use Mail::Box::Manager;"; 
    if ($@) { require Test::More; Test::More->import(skip_all =>
        "You don't have Mail::Box::Manager"); exit; }
}

use Test::More tests => 3;
use_ok("Mail::Thread");
my $mgr = new Mail::Box::Manager;
my $box = $mgr->open(folder => "t/testbox");

my $threader = new Mail::Thread($box->messages);

$threader->thread;

is($threader->rootset, 3, "We have three main threads");

my @stuff;
for ($threader->rootset) {
    dump_em($_, 0);
}

sub dump_em {
    my ($self, $level) = @_;
    push @stuff, 
    [ $level, eval { "".$self->message->head->get("Subject") }
             || "[ Message not available ]" ];
    dump_em($self->next, $level) if $self->next;
    dump_em($self->child, $level+1) if $self->child;
}

is_deeply(\@stuff,
 [
          [ 0, '[rt-users] Configuration Problem' ],
          [ 1, 'Re: [rt-users] Configuration Problem' ],
          [ 0, 'Re: January\'s meeting' ],
          [ 1, 'Re: January\'s meeting' ],
          [ 2, 'Re: January\'s meeting' ],
          [ 0, '[ Message not available ]' ],
          [ 1, '[p5ml] Re: karie kahimi binge...help needed' ],
          [ 1, 'Re: [p5ml] karie kahimi binge...help needed' ],
          [ 1, 'R: [p5ml] karie kahimi binge...help needed' ],
          [ 2, 'Re: [p5ml] karie kahimi binge...help needed' ],
          [ 2, 'RE: [p5ml] Re: karie kahimi binge...help needed' ]
        ], "It all works");

