#!/usr/bin/env perl

use lib qw(); # PERL5LIB
use FindBin;use lib "$FindBin::Bin/../lib";use lib "$FindBin::Bin/../thirdparty/lib/perl5"; # LIBDIR

# having a non-C locale for number will wreck all sorts of havoc
# when things get converted to string and back
use POSIX qw(locale_h);
setlocale(LC_NUMERIC, "C");

use Mojolicious::Lite;
use IPC::Open3;
use Symbol 'gensym';

die "SMBPASSWD_SMB_HOST environment variable is not defined\n"
   unless $ENV{SMBPASSWD_SMB_HOST};


# Make signed cookies secure
app->secrets(['dontneedsecurecookies in this app']);

# Fix URLs in reverse proxy mode.
if ( my $path = $ENV{MOJO_REVERSE_PROXY} ) {
    my @path_parts = grep /\S/, split m{/}, $path;
    app->hook( before_dispatch => sub {
        my ( $c ) = @_;
        my $url = $c->req->url;
        my $base = $url->base;
        push @{ $base->path }, @path_parts;
        $base->path->trailing_slash(1);
        $url->path->leading_slash(0);
    });
}

my $errors = {
    size => sub {
        my ($value,$min,$max) = @_;
        return "Size is must be between $min and $max";
    },
    equal_to => sub {
        my ($value,$key) = @_;
        return "must be equal to '$key'";
    },
    required => sub {
        "entry is mandatory"
    },
    passwordQuality => sub {
        my ($value) = @_;
        return qq{$value expected. See <a href="https://uit.stanford.edu/service/accounts/passwords/quickguide" target="_blank">Help</a> for inspiration.};
    },
    errmsg => sub {
        shift;
    },
};

helper(
    errtext => sub {
        my $c = shift;
        my $err = shift;
        my ($check, $result, @args) = @$err;
        return $errors->{$check}->($result,@args);
    }
);

my $passwordQuality = sub {
    my ($validation, $name, $value) = @_;
    my $len = length $value;
    return "Lowercase letters" if $value !~ /[a-z]/;
    return undef if $len >= 20;
    return "Uppercase letters" if $value !~ /[A-Z]/;
    return undef if $len >= 16;
    return "Numbers" if $value !~ /[0-9]/;
    return undef if $len >= 12;
    return 'Symbols like $%#@.; ...' if $value !~ /[^\sa-zA-Z0-9]/;
    return undef if $len >= 8;
    return "At least 8 characters";
};

# Main login action
any '/' => sub {
    my $c = shift;
    my $validation = $c->validation;
    return $c->render unless $validation->has_data;

    $validation->validator->add_check(passwordQuality => $passwordQuality);

    $validation->required('user')->size(1, 20);
    $validation->required('pass')->size(1,80);
    if (!$ENV{SMBPASSWD_NO_QUALITY_CHECK}){
        $validation->required('newpass')->passwordQuality();
    }
    $validation->required('newpass_again')->equal_to('newpass');

    return $c->render if $validation->has_error;

    my $user = $c->param('user');
    my $pass = $c->param('pass');
    my $newpass = $c->param('newpass');
    my($wtr, $rdr, $err);
    $err = gensym;
    warn "### calling smbpasswd";
    my $pid = open3($wtr, $rdr, $err,
        "/usr/bin/smbpasswd","-U",$user,"-r","$ENV{SMBPASSWD_SMB_HOST}","-s");
    print $wtr "$pass\n$newpass\n$newpass\n";
    waitpid( $pid, 0 );
    if ($?){
        warn "something went wrong";
        $c->flash(message=>"failed to set smb password".<$err>);
        return $c->redirect_to('index');
    }
    $c->render('thanks');
}=>"index";


app->start;
__DATA__

@@ layouts/default.html.ep
<!DOCTYPE html>
<html lang="en" >
  <head>
    <!-- Latest compiled and minified CSS -->
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css">
  </head>
  <body>
  <title><%= title %></title>
</head>
<body>
<div class="container">
  <div class="row">
      <%= content %>
  </div>
</div>
</body>
</html>

@@ index.html.ep
% layout 'default';
% title 'Samba Password Setter';

<div class="col-md-4 col-md-offset-4 col-sm-6 col-sm-offset-3">
<h1>Password Reset</h1>

<div>
% my @fields = qw(user pass newpass newpass_again);
% my %fields = ( user => 'Username', pass => 'Password', newpass => 'New Password', newpass_again => 'New Password Again');
% my $msg = flash('message');

%= form_for current => method=> 'post' => begin
  <fieldset>
%  for my $field (@fields){
%      my $err = validation->error($field);
%      if ($field eq 'pass' and $msg and $msg =~ /invalid credential/i){
%           $err = [ errmsg => 'Invalid Credentials'];
%           $msg = undef;
%      }
  <div class="form-group <%= $err ? 'has-error' : '' %>">
%=   label_for $field => $fields{$field} => class => 'control-label'
%      if ($field =~ /pass/){
%=         input_tag $field => class=>'form-control', type => 'password';
%      }
%      else {
%=         text_field $field => class=>'form-control'
%      }
%      if ($err) {
        <span class="help-block"><%== errtext($err) %></span>
%      }
  </div>
%  }
  </fieldset>
  % if ($msg) {
  <div class="panel panel-danger">
    <div class="panel-heading">PROBLEM!</div>
    <div class="panel-body">
    %= $msg
    </div>
  </div>
  % }

  %= submit_button 'Set Password' => class=>"btn btn-primary col-xs-12"
% end
</div>
</div>


@@ thanks.html.ep
% layout 'default';

<div class="col-sm-6 col-sm-offset-3">
<div class="jumbotron">
    <div class="container">
    <h1>Success!</h1>
    <p>
        The password of user <em><%= validation->param('user') %></em> has been updated.
    </p>
</div>
</div>
