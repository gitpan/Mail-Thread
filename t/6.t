BEGIN { eval "use Mail::Box::Manager;"; 
    if ($@) { require Test::More; Test::More->import(skip_all =>
        "You don't have Mail::Box::Manager"); exit; }
}

use Test::More tests => 2;
use_ok("Mail::Thread");
my $mgr = new Mail::Box::Manager;
my $box = $mgr->open(folder => "t/testbox-6");

my $threader = new Mail::Thread($box->messages);
$threader->thread;

ok(2, "Avoid loops at all cost");
