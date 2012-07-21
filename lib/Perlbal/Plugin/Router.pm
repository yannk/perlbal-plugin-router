package Perlbal::Plugin::Router;

use strict;
use warnings;
no  warnings qw(deprecated);

our $VERSION = '0.0.1';

=head1 NAME

Perlbal::Plugin::Router

=head1 DESCRIPTION

This Perlbal selector plugin allow to route the traffic to a bunch of secondary
Perlbal services depending on a combination of HTTP Methods and URI paths.

The URI Paths can be configured using Regular expressions which are evaluated
at runtime against incoming requests. See also standard
L<Perlbal::Plugin::VPaths>.

Example:

  LOAD Router
  CREATE SERVICE super_selector
    SET listen                = 0.0.0.0:10081
    SET role                  = selector
    SET plugins               = Router
    ROUTE POST ^/cats/        = cat_service
    ROUTE POST .*             = lol_service
    ROUTE ANY  .*             = default_service
  ENABLE super_selector

=cut

## this is an extension of Perlbal's standard VPATH handling

our %Services;  # service_name => $svc

# when "LOAD" directive loads us up
sub load {
    my $class = shift;

    Perlbal::register_global_hook('manage_command.route', sub {
        my $mc = shift->parse(qr/^route\s+(?:(\w+)\s+)?(\w+)\s+(\S+)\s*=\s*(\w+)$/,
                              "usage: ROUTE [<service>] <verb> <path regex> = <dest_service>");
        my ($selname, $method, $regex, $target) = $mc->args;
        unless ($selname ||= $mc->{ctx}{last_created}) {
            return $mc->err("omitted service name not implied from context");
        }

        my $ss = Perlbal->service($selname);
        return $mc->err("Service '$selname' is not a selector service")
            unless $ss && $ss->{role} eq "selector";

        my $cregex = qr/$regex/;
        return $mc->err("invalid regular expression: '$regex'")
            unless $cregex;

        $ss->{extra_config}->{_routes} ||= [];
        push @{$ss->{extra_config}->{_routes}}, [ uc $method, $cregex, $target ];

        return $mc->ok;
    });
    return 1;
}

# unload our global commands, clear our service object
sub unload {
    my $class = shift;

    Perlbal::unregister_global_hook('manage_command.route');
    unregister($class, $_) foreach (values %Services);
    return 1;
}

# called when we're being added to a service
sub register {
    my ($class, $svc) = @_;
    unless ($svc && $svc->{role} eq "selector") {
        die "You can't load the ROUTER plugin on a service not of role selector.\n";
    }

    $svc->selector(\&route_selector);
    $svc->{extra_config}->{_routes} = [];

    $Services{"$svc"} = $svc;
    return 1;
}

# called when we're no longer active on a service
sub unregister {
    my ($class, $svc) = @_;
    $svc->selector(undef);
    delete $Services{"$svc"};
    return 1;
}

# call back from Service via ClientHTTPBase's event_read calling service->select_new_service(Perlbal::ClientHTTPBase)
sub route_selector {
    my Perlbal::ClientHTTPBase $cb = shift;

    my $req = $cb->{req_headers};
    return $cb->_simple_response(404, "Not Found (no reqheaders)") unless $req;

    my $uri = $req->request_uri;
    my $maps = $cb->{service}{extra_config}{_routes} ||= {};

    # iterate down the list of paths, find any matches
    my $method = $req->request_method || "";
    foreach my $row (@$maps) {
        next unless $method eq $row->[0] or $row->[0] eq 'ANY';
        next unless $uri =~ /$row->[1]/;

        my $svc_name = $row->[2];
        my $svc = $svc_name ? Perlbal->service($svc_name) : undef;
        unless ($svc) {
            $cb->_simple_response(
                404 => "Not Found ($svc_name not a defined service)",
            );
            return 1;
        }

        $svc->adopt_base_client($cb);
        return 1;
    }

    return 0;
}

1;
