package Travel::Status::DE::IRIS::Result;

use strict;
use warnings;
use 5.014;
use utf8;

use parent 'Class::Accessor';
use Carp qw(cluck);
use DateTime;
use DateTime::Format::Strptime;
use List::Compare;
use List::Util      qw(any);
use List::MoreUtils qw(uniq lastval);
use Scalar::Util    qw(weaken);

our $VERSION = '1.99';

Travel::Status::DE::IRIS::Result->mk_ro_accessors(
	qw(arrival arrival_delay arrival_has_realtime arrival_is_additional arrival_is_cancelled arrival_hidden
	  date datetime delay
	  departure departure_delay departure_has_realtime departure_is_additional departure_is_cancelled departure_hidden
	  ds100 has_realtime is_transfer is_unscheduled is_wing
	  line_no old_train_id old_train_no operator platform raw_id
	  realtime_xml route_start route_end
	  sched_arrival sched_departure sched_platform sched_route_start
	  sched_route_end start
	  station station_eva station_uic
	  stop_no time train_id train_no transfer type
	  unknown_t unknown_o wing_id wing_of)
);

# {{{ Data (message codes, station fixups)

my %translation = (
	1  => 'Nähere Informationen in Kürze',
	2  => 'Polizeieinsatz',
	3  => 'Feuerwehreinsatz auf der Strecke',
	4  => 'Kurzfristiger Personalausfall',            # xlsx: missing
	5  => 'Ärztliche Versorgung eines Fahrgastes',
	6  => 'Betätigen der Notbremse',   # xlsx: "Unbefugtes Ziehen der Notbremse"
	7  => 'Unbefugte Personen auf der Strecke',
	8  => 'Notarzteinsatz auf der Strecke',
	9  => 'Streikauswirkungen',
	10 => 'Tiere auf der Strecke',
	11 => 'Unwetter',
	12 => 'Warten auf ein verspätetes Schiff',
	13 => 'Pass- und Zollkontrolle',
	14 => 'Defekt am Bahnhof',         # xlsx: "Technischer Defekt am Bahnhof"
	15 => 'Beeinträchtigung durch Vandalismus',
	16 => 'Entschärfung einer Fliegerbombe',
	17 => 'Beschädigung einer Brücke',
	18 => 'Umgestürzter Baum auf der Strecke',
	19 => 'Unfall an einem Bahnübergang',
	20 => 'Tiere im Gleis',                           # xlsx: missing
	21 => 'Warten auf Anschlussreisende',
	22 => 'Witterungsbedingte Beeinträchtigung',
	23 => 'Betriebsstabilisierung',
	24 => 'Verspätung im Ausland',
	25 => 'Bereitstellung weiterer Wagen',
	26 => 'Abhängen von Wagen',
	27 => 'Technische Störung am Bus',
	28 => 'Gegenstände auf der Strecke',
	29 => 'Ersatzverkehr mit Bus ist eingerichtet',
	31 => 'Bauarbeiten',
	32 => 'Längere Haltezeit am Bahnhof',
	33 => 'Defekt an der Oberleitung',    # xlsx: "Reparatur an der Oberleitung"
	34 => 'Defekt an einem Signal',       # xlsx: "Reparatur an einem Signal"
	35 => 'Streckensperrung',
	36 => 'Technische Störung am Zug',
	37 => 'Kurzfristiger Fahrzeugausfall',
	38 => 'Defekt an der Strecke',        # xlsx: "Reparatur an der Strecke"
	39 => 'Stau / Hohes Verkehrsaufkommen',
	40 => 'Defektes Stellwerk',
	41 => 'Defekt an einem Bahnübergang'
	,    # xlsx: "Technischer Defekt an einem Bahnüburgang"
	42 => 'Außerplanmäßige Geschwindigkeitsbeschränkung'
	,    # xlsx: "Vorübergehend verminderte Geschwindigkeit auf der Strecke"
	43 => 'Verspätung eines vorausfahrenden Zuges',
	44 => 'Warten auf einen entgegenkommenden Zug',
	45 => 'Vorfahrt eines anderen Zuges',
	46 => 'Vorfahrt eines anderen Zuges',

	47 => 'Verspätete Bereitstellung',
	48 => 'Verspätung aus vorheriger Fahrt',
	49 => 'Kurzfristiger Personalausfall',
	50 => 'Kurzfristige Erkrankung von Personal',
	51 => 'Verspätetes Personal aus vorheriger Fahrt',
	52 => 'Streik',
	53 => 'Unwetterauswirkungen',
	54 => 'Verfügbarkeit der Gleise derzeit eingeschränkt',
	55 => 'Technischer Defekt an einem anderen Zug',
	56 => 'Warten auf Anschlussreisende',                     # aus einem Bus
	57 => 'Zusätzlicher Halt', # xslx: "Zusätzlicher Halt zum Ein- und Ausstieg"
	58 => 'Umleitung',         # xlsx: "Umleitung des Zuges"
	59 => 'Schnee und Eis',
	60 => 'Witterungsbedingt verminderte Geschwindigkeit',
	61 => 'Defekte Tür',
	62 => 'Behobener Defekt am Zug',
	63 => 'Technische Untersuchung am Zug',
	64 => 'Defekt an einer Weiche',
	65 => 'Erdrutsch',
	66 => 'Hochwasser',
	67 => 'Behördliche Maßnahme',
	68 => 'Hohes Fahrgastaufkommen'
	,    # xlsx: "Hohes Fahrgastaufkommen verlängert Ein- und Ausstieg"
	69 => 'Zug verkehrt mit verminderter Geschwindigeit',
	70 => 'WLAN nicht verfügbar',
	71 => 'WLAN in einzelnen Wagen nicht verfügbar',
	72 => 'Info/Entertainment nicht verfügbar',
	73 => 'Heute: Mehrzweckabteil vorne',
	74 => 'Heute: Mehrzweckabteil hinten',
	75 => 'Heute: 1. Klasse vorne',
	76 => 'Heute: 1. Klasse hinten',
	77 => '1. Klasse fehlt',
	78 => 'Ersatzverkehr mit Bus ist eingerichtet',
	79 => 'Mehrzweckabteil fehlt',
	80 => 'Abweichende Wagenreihung',
	81 => 'Fahrzeugtausch',
	82 => 'Mehrere Wagen fehlen',
	83 => 'Defekte fahrzeuggebundene Einstiegshilfe',
	84 => 'Zug verkehrt richtig gereiht',
	85 => 'Ein Wagen fehlt',
	86 => 'Gesamter Zug ohne Reservierung',
	87 => 'Einzelne Wagen ohne Reservierung',
	88 => 'Keine Qualitätsmängel',
	89 => 'Reservierungen sind wieder vorhanden',
	90 => 'Kein gastronomisches Angebot',
	91 => 'Fahrradmitnahme nicht möglich',
	92 => 'Eingeschränkte Fahrradbeförderung',
	93 => 'Behindertengerechte Einrichtung fehlt',
	94 => 'Ersatzbewirtschaftung',
	95 => 'Universal-WC fehlt',
	96 => 'Überbesetzung mit Kulanzleistungen',
	97 => 'Überbesetzung ohne Kulanzleistungen',
	98 => 'Sonstige Qualitätsmängel',
	99 => 'Verzögerungen im Betriebsablauf',

	# Occasionally, there's a message with ID 900. In all cases observed so far,
	# it was used for "Anschlussbus wartet". However, as we don't know which bus
	# it refers to, we don't show it to users.
);

# IRIS may return "Betriebsstelle nicht bekannt" for some recently added
# stations. Fix those manually.
my %fixup = (
	8002795 => 'Herten(Westf)',
	8003983 => 'Merklingen - Schwäbische Alb',
	8005493 => 'Schwetzingen-Hirschacker',
	8070678 => 'Metzingen-Neuhausen',
);

# }}}
# {{{ Constructor

sub new {
	my ( $obj, %opt ) = @_;

	my $ref = \%opt;

	my ( $train_id, $start_ts, $stop_no ) = split( /.\K-/, $opt{raw_id} );

	bless( $ref, $obj );

	$ref->{strptime_obj} //= DateTime::Format::Strptime->new(
		pattern   => '%y%m%d%H%M',
		time_zone => 'Europe/Berlin',
	);

	$ref->{wing_id} = "${train_id}-${start_ts}";
	$ref->{is_wing} = 0;
	$train_id =~ s{^-}{};

	$ref->{start} = $ref->parse_ts($start_ts);

	$ref->{train_id} = $train_id;
	$ref->{stop_no}  = $stop_no;

	if ( $opt{transfer} ) {
		my ($transfer) = split( /.\K-/, $opt{transfer} );
		$transfer =~ s{^-}{};
		$ref->{transfer} = $transfer;
	}

	my $ar = $ref->{arrival} = $ref->{sched_arrival}
	  = $ref->parse_ts( $opt{arrival_ts} );
	my $dp = $ref->{departure} = $ref->{sched_departure}
	  = $ref->parse_ts( $opt{departure_ts} );

	if ( not( defined $ar or defined $dp ) ) {
		cluck(
			sprintf(
				"Neither arrival '%s' nor departure '%s' are valid "
				  . "timestamps - can't handle this train",
				$opt{arrival_ts}, $opt{departure_ts}
			)
		);
	}

	my $dt = $ref->{datetime} = $dp // $ar;

	$ref->{date}  = $dt->strftime('%d.%m.%Y');
	$ref->{time}  = $dt->strftime('%H:%M');
	$ref->{epoch} = $dt->epoch;

	$ref->{route_pre} = $ref->{sched_route_pre}
	  = [ split( qr{[|]}, $ref->{route_pre} // q{} ) ];
	$ref->{route_post} = $ref->{sched_route_post}
	  = [ split( qr{[|]}, $ref->{route_post} // q{} ) ];

	$ref->fixup_route( $ref->{route_pre} );
	$ref->fixup_route( $ref->{route_post} );

	$ref->{route_pre_incomplete}  = $ref->{route_end}  ? 1 : 0;
	$ref->{route_post_incomplete} = $ref->{route_post} ? 1 : 0;

	$ref->{sched_platform} = $ref->{platform};
	$ref->{route_end}
	  = $ref->{sched_route_end}
	  = $ref->{route_end}
	  || $ref->{route_post}[-1]
	  || $ref->{station};
	$ref->{route_start}
	  = $ref->{sched_route_start}
	  = $ref->{route_start}
	  || $ref->{route_pre}[0]
	  || $ref->{station};

	return $ref;
}

# }}}
# {{{ Internal Helpers

sub fixup_route {
	my ( $self, $route ) = @_;
	for my $stop ( @{$route} ) {
		if ( $stop =~ m{^Betriebsstelle nicht bekannt (\d+)$} ) {
			if ( $fixup{$1} ) {
				$stop = $fixup{$1};
			}
		}
	}
}

sub parse_ts {
	my ( $self, $string ) = @_;

	if ( defined $string ) {
		return $self->{strptime_obj}->parse_datetime($string);
	}
	return;
}

# List::Compare does not keep the order of its arguments (even with unsorted).
# So we need to re-sort all stops to maintain their original order.
sub sorted_sublist {
	my ( $self, $list, $sublist ) = @_;
	my %pos;

	if ( not $sublist or not @{$sublist} ) {
		return;
	}

	for my $i ( 0 .. $#{$list} ) {
		$pos{ $list->[$i] } = $i;
	}

	my @sorted = sort { $pos{$a} <=> $pos{$b} } @{$sublist};

	return @sorted;
}

sub superseded_messages {
	my ( $self, $msg ) = @_;
	my %superseded = (
		62 => [36],
		73 => [74],
		74 => [73],
		75 => [76],
		76 => [75],
		84 => [ 73, 74, 75, 76, 80 ],
		88 => [
			70, 71, 72, 77, 79, 82, 83, 85, 90, 91, 92, 93, 94, 95, 96, 97, 98
		],
		89 => [ 86, 87 ],
	);

	return @{ $superseded{$msg} // [] };
}

# }}}
# {{{ Internal Setters for IRIS.pm

sub set_ar {
	my ( $self, %attrib ) = @_;

	if ( $attrib{status} and $attrib{status} eq 'c' ) {
		$self->{has_realtime}         = $self->{arrival_has_realtime} = 1;
		$self->{arrival_is_cancelled} = 1;
	}
	elsif ( $attrib{status} and $attrib{status} eq 'a' ) {
		$self->{arrival_is_additional} = 1;
	}
	else {
		$self->{arrival_is_additional} = 0;
		$self->{arrival_is_cancelled}  = 0;
	}

	if ( $attrib{arrival_hidden} ) {
		$self->{arrival_hidden} = $attrib{arrival_hidden};
	}

	# unscheduled arrivals may not appear in the plan, but we do need to
	# know their planned arrival time
	if ( $attrib{plan_arrival_ts} ) {
		$self->{sched_arrival}
		  = $self->parse_ts( $attrib{plan_arrival_ts} );
	}

	if ( $attrib{arrival_ts} ) {
		$self->{has_realtime} = $self->{arrival_has_realtime} = 1;
		$self->{arrival}      = $self->parse_ts( $attrib{arrival_ts} );
		if ( not $self->{arrival_is_cancelled} ) {
			$self->{delay} = $self->{arrival_delay}
			  = $self->arrival->subtract_datetime( $self->sched_arrival )
			  ->in_units('minutes');
		}
	}
	else {
		$self->{arrival} = $self->{sched_arrival};
		$self->{arrival_delay} //= 0;
		$self->{delay}         //= 0;
	}

	if ( $attrib{platform} ) {
		$self->{platform} = $attrib{platform};
	}
	else {
		$self->{platform} = $self->{sched_platform};
	}

	if ( defined $attrib{route_pre} ) {
		$self->{route_pre} = [ split( qr{[|]}, $attrib{route_pre} // q{} ) ];
		$self->fixup_route( $self->{route_pre} );
		if ( @{ $self->{route_pre} } ) {
			$self->{route_start} = $self->{route_pre}[0];
		}
	}
	else {
		$self->{route_pre}   = $self->{sched_route_pre};
		$self->{route_start} = $self->{sched_route_start};
	}

	# also only for unscheduled arrivals
	if ( $attrib{sched_route_pre} ) {
		$self->{sched_route_pre}
		  = [ split( qr{[|]}, $attrib{sched_route_pre} // q{} ) ];
		$self->fixup_route( $self->{sched_route_pre} );
		$self->{sched_route_start} = $self->{sched_route_pre}[0];
	}

	return $self;
}

sub set_dp {
	my ( $self, %attrib ) = @_;

	if ( $attrib{status} and $attrib{status} eq 'c' ) {
		$self->{has_realtime}           = $self->{arrival_has_realtime} = 1;
		$self->{departure_is_cancelled} = 1;
	}
	elsif ( $attrib{status} and $attrib{status} eq 'a' ) {
		$self->{departure_is_additional} = 1;
	}
	else {
		$self->{departure_is_additional} = 0;
		$self->{departure_is_cancelled}  = 0;
	}

	if ( $attrib{departure_hidden} ) {
		$self->{departure_hidden} = $attrib{departure_hidden};
	}

	# unscheduled arrivals may not appear in the plan, but we do need to
	# know their planned arrival time
	if ( $attrib{plan_departure_ts} ) {
		$self->{sched_departure}
		  = $self->parse_ts( $attrib{plan_departure_ts} );
	}

	if ( $attrib{departure_ts} ) {
		$self->{has_realtime} = $self->{departure_has_realtime} = 1;
		$self->{departure}    = $self->parse_ts( $attrib{departure_ts} );
		if ( not $self->{departure_is_cancelled} ) {
			$self->{delay} = $self->{departure_delay}
			  = $self->departure->subtract_datetime( $self->sched_departure )
			  ->in_units('minutes');
		}
	}
	else {
		$self->{departure} = $self->{sched_departure};
		$self->{delay}           //= 0;
		$self->{departure_delay} //= 0;
	}

	if ( $attrib{platform} ) {
		$self->{platform} = $attrib{platform};
	}
	else {
		$self->{platform} = $self->{sched_platform};
	}

	if ( defined $attrib{route_post} ) {
		$self->{route_post} = [ split( qr{[|]}, $attrib{route_post} // q{} ) ];
		$self->fixup_route( $self->{route_post} );
		if ( @{ $self->{route_post} } ) {
			$self->{route_end} = $self->{route_post}[-1];
		}
	}
	else {
		$self->{route_post} = $self->{sched_route_post};
		$self->{route_end}  = $self->{sched_route_end};
	}

	# also only for unscheduled departures
	if ( $attrib{sched_route_post} ) {
		$self->{sched_route_post}
		  = [ split( qr{[|]}, $attrib{sched_route_post} // q{} ) ];
		$self->fixup_route( $self->{sched_route_post} );
		$self->{sched_route_end} = $self->{sched_route_post}[-1];
	}

	return $self;
}

sub set_messages {
	my ( $self, %messages ) = @_;

	$self->{messages} = \%messages;

	return $self;
}

sub set_realtime {
	my ( $self, $xmlobj ) = @_;

	$self->{realtime_xml} = $xmlobj;

	return $self;
}

sub add_raw_ref {
	my ( $self, %attrib ) = @_;

	push( @{ $self->{refs} }, \%attrib );

	return $self;
}

sub set_unscheduled {
	my ( $self, $unscheduled ) = @_;

	$self->{is_unscheduled} = $unscheduled;

	return $self;
}

sub add_arrival_wingref {
	my ( $self, $ref ) = @_;

	my $backref = $self;

	weaken($ref);
	weaken($backref);
	$ref->{is_wing} = 1;
	$ref->{wing_of} = $backref;
	push( @{ $self->{arrival_wings} }, $ref );
	return $self;
}

sub add_departure_wingref {
	my ( $self, $ref ) = @_;

	my $backref = $self;

	weaken($ref);
	weaken($backref);
	$ref->{is_wing} = 1;
	$ref->{wing_of} = $backref;
	push( @{ $self->{departure_wings} }, $ref );
	return $self;
}

sub add_reference {
	my ( $self, $ref ) = @_;

	$ref->add_inverse_reference($self);
	weaken($ref);
	push( @{ $self->{replacement_for} }, $ref );
	return $self;
}

sub merge_with_departure {
	my ( $self, $result ) = @_;

	# result must be departure-only

	$self->{is_transfer} = 1;

	$self->{old_train_id} = $self->{train_id};
	$self->{old_train_no} = $self->{train_no};

	# departure is preferred over arrival, so overwrite default values
	$self->{date}     = $result->{date};
	$self->{time}     = $result->{time};
	$self->{epoch}    = $result->{epoch};
	$self->{datetime} = $result->{datetime};
	$self->{train_id} = $result->{train_id};
	$self->{train_no} = $result->{train_no};

	$self->{departure}        = $result->{departure};
	$self->{departure_wings}  = $result->{departure_wings};
	$self->{route_end}        = $result->{route_end};
	$self->{route_post}       = $result->{route_post};
	$self->{sched_departure}  = $result->{sched_departure};
	$self->{sched_route_post} = $result->{sched_route_post};

	# update realtime info only if applicable
	$self->{is_cancelled} ||= $result->{is_cancelled};

	return $self;
}

sub add_inverse_reference {
	my ( $self, $ref ) = @_;

	weaken($ref);
	push( @{ $self->{replaced_by} }, $ref );
	return $self;
}

# }}}
# {{{ Public Accessors

sub is_additional {
	my ($self) = @_;

	if ( $self->{arrival_is_additional} and $self->{departure_is_additional} ) {
		return 1;
	}
	if ( $self->{arrival_is_additional}
		and not defined $self->{departure_is_additional} )
	{
		return 1;
	}
	if ( not defined $self->{arrival_is_additional}
		and $self->{departure_is_additional} )
	{
		return 1;
	}
	return 0;
}

sub is_cancelled {
	my ($self) = @_;

	if ( $self->{arrival_is_cancelled} and $self->{departure_is_cancelled} ) {
		return 1;
	}
	if ( $self->{arrival_is_cancelled}
		and not defined $self->{departure_is_cancelled} )
	{
		return 1;
	}
	if ( not defined $self->{arrival_is_cancelled}
		and $self->{departure_is_cancelled} )
	{
		return 1;
	}
	return 0;
}

sub additional_stops {
	my ($self) = @_;

	$self->{comparator} //= List::Compare->new(
		{
			lists    => [ $self->{sched_route_post}, $self->{route_post} ],
			unsorted => 1,
		}
	);

	return $self->sorted_sublist( $self->{route_post},
		[ $self->{comparator}->get_complement ] );
}

sub canceled_stops {
	my ($self) = @_;

	$self->{comparator} //= List::Compare->new(
		{
			lists    => [ $self->{sched_route_post}, $self->{route_post} ],
			unsorted => 1,
		}
	);

	return $self->sorted_sublist( $self->{sched_route_post},
		[ $self->{comparator}->get_unique ] );
}

sub classes {
	my ($self) = @_;

	my @classes = split( //, $self->{classes} // q{} );

	return @classes;
}

sub origin {
	my ($self) = @_;

	return $self->route_start;
}

sub destination {
	my ($self) = @_;

	return $self->route_end;
}

sub delay_messages {
	my ($self) = @_;

	my @keys   = sort keys %{ $self->{messages} };
	my @msgs   = grep { $_->[1] eq 'd' } map { $self->{messages}{$_} } @keys;
	my @msgids = uniq( map { $_->[2] } @msgs );
	my @ret;

	for my $id (@msgids) {
		for my $superseded ( $self->superseded_messages($id) ) {
			@ret = grep { not( $_->[2] == $superseded ) } @ret;
		}
		my $msg = lastval { $_->[2] == $id } @msgs;
		push( @ret, $msg );
	}

	@ret = reverse
	  map { [ $self->parse_ts( $_->[0] ), $self->translate_msg( $_->[2] ) ] }
	  @ret;

	return @ret;
}

sub arrival_wings {
	my ($self) = @_;

	if ( $self->{arrival_wings} ) {
		return @{ $self->{arrival_wings} };
	}
	return;
}

sub departure_wings {
	my ($self) = @_;

	if ( $self->{departure_wings} ) {
		return @{ $self->{departure_wings} };
	}
	return;
}

sub replaced_by {
	my ($self) = @_;

	if ( $self->{replaced_by} ) {
		return @{ $self->{replaced_by} };
	}
	return;
}

sub replacement_for {
	my ($self) = @_;

	if ( $self->{replacement_for} ) {
		return @{ $self->{replacement_for} };
	}
	return;
}

sub qos_messages {
	my ($self) = @_;

	my @keys = sort keys %{ $self->{messages} };
	my @msgs
	  = grep { $_->[1] =~ m{^[fq]$} } map { $self->{messages}{$_} } @keys;
	my @ret;

	for my $msg (@msgs) {
		for my $superseded ( $self->superseded_messages( $msg->[2] ) ) {
			@ret = grep { not( $_->[2] == $superseded ) } @ret;
		}
		@ret = grep { $_->[2] != $msg->[2] } @ret;

		# 88 is "no qos shortcomings" and only required to cancel previous qos
		# messages. Same for 84 ("correct wagon order") and 89 ("reservations
		# display is working again").
		if ( $msg->[2] != 84 and $msg->[2] != 88 and $msg->[2] != 89 ) {
			push( @ret, $msg );
		}
	}

	@ret
	  = map { [ $self->parse_ts( $_->[0] ), $self->translate_msg( $_->[2] ) ] }
	  reverse @ret;

	return @ret;
}

sub raw_messages {
	my ($self) = @_;

	my @messages = reverse sort keys %{ $self->{messages} };
	my @ret      = map {
		[
			$self->parse_ts( $self->{messages}->{$_}->[0] ),
			$self->{messages}->{$_}->[2]
		]
	} @messages;

	return @ret;
}

sub messages {
	my ($self) = @_;

	my @messages = reverse sort keys %{ $self->{messages} };
	my @ret      = map {
		[
			$self->parse_ts( $self->{messages}->{$_}->[0] ),
			$self->translate_msg( $self->{messages}->{$_}->[2] )
		]
	} @messages;

	return @ret;
}

sub info {
	my ($self) = @_;

	my @messages = sort keys %{ $self->{messages} };
	my @ids      = uniq( map { $self->{messages}{$_}->[2] } @messages );

	my @info = map { $self->translate_msg($_) } @ids;

	return @info;
}

sub line {
	my ($self) = @_;

	return sprintf( '%s %s',
		$self->{type} // 'Zug',
		$self->{line_no} // $self->{train_no} // '-' );
}

sub route_pre {
	my ($self) = @_;

	return @{ $self->{route_pre} };
}

sub route_post {
	my ($self) = @_;

	return @{ $self->{route_post} };
}

sub route {
	my ($self) = @_;

	return ( $self->route_pre, $self->{station}, $self->route_post );
}

sub train {
	my ($self) = @_;

	return $self->line;
}

sub route_interesting {
	my ( $self, $max_parts ) = @_;

	my @via = $self->route_post;
	my ( @via_main, @via_show, $last_stop );
	$max_parts //= 3;

	# Centraal: dutch main station (Hbf in .nl)
	# HB:  swiss main station (Hbf in .ch)
	# hl.n.: czech main station (Hbf in .cz)
	for my $stop (@via) {
		if ( $stop =~ m{ HB $ | hl\.n\. $ | Hbf | Centraal | Flughafen }x ) {
			push( @via_main, $stop );
		}
	}
	$last_stop
	  = $self->{route_post_incomplete} ? $self->{route_end} : pop(@via);

	if ( @via_main and $via_main[-1] eq $last_stop ) {
		pop(@via_main);
	}
	if ( @via and $via[-1] eq $last_stop ) {
		pop(@via);
	}

	if ( @via_main and @via and $via[0] eq $via_main[0] ) {
		shift(@via_main);
	}

	if ( @via < $max_parts ) {
		@via_show = @via;
	}
	else {
		if ( @via_main >= $max_parts ) {
			@via_show = ( $via[0] );
		}
		else {
			@via_show = splice( @via, 0, $max_parts - @via_main );
		}

		while ( @via_show < $max_parts and @via_main ) {
			my $stop = shift(@via_main);
			if ( any { $stop eq $_ } @via_show or $stop eq $last_stop ) {
				next;
			}
			push( @via_show, $stop );
		}
	}

	for (@via_show) {
		s{ \s? Hbf .* }{}x;
	}

	return @via_show;

}

sub sched_route_pre {
	my ($self) = @_;

	return @{ $self->{sched_route_pre} };
}

sub sched_route_post {
	my ($self) = @_;

	return @{ $self->{sched_route_post} };
}

sub sched_route {
	my ($self) = @_;

	return ( $self->sched_route_pre, $self->{station},
		$self->sched_route_post );
}

sub translate_msg {
	my ( $self, $msg ) = @_;

	return $translation{$msg} // "?($msg)";
}

sub TO_JSON {
	my ($self) = @_;

	my %copy = %{$self};
	delete $copy{realtime_xml};
	delete $copy{strptime_obj};

	for my $ref_key (
		qw(arrival_wings departure_wings replaced_by replacement_for))
	{
		delete $copy{$ref_key};
		for my $train_ref ( @{ $self->{$ref_key} // [] } ) {
			push(
				@{ $copy{$ref_key} },
				{
					raw_id   => $train_ref->raw_id,
					train    => $train_ref->train,
					train_no => $train_ref->train_no,
					type     => $train_ref->type,
				}
			);
		}
	}

	delete $copy{wing_of};
	if ( my $train_ref = $self->wing_of ) {
		$copy{wing_of} = {
			raw_id   => $train_ref->raw_id,
			train    => $train_ref->train,
			train_no => $train_ref->train_no,
			type     => $train_ref->type,
		};
	}

	for my $datetime_key (
		qw(arrival departure sched_arrival sched_departure start datetime))
	{
		if ( defined $copy{$datetime_key} ) {
			$copy{$datetime_key} = $copy{$datetime_key}->epoch;
		}
	}

	return {%copy};
}

# }}}

1;

__END__

=head1 NAME

Travel::Status::DE::IRIS::Result - Information about a single
arrival/departure received by Travel::Status::DE::IRIS

=head1 SYNOPSIS

	for my $result ($status->results) {
		printf(
			"At %s: %s to %s from platform %s\n",
			$result->time,
			$result->line,
			$result->destination,
			$result->platform,
		);
	}

=head1 VERSION

version 1.99

=head1 DESCRIPTION

Travel::Status::DE::IRIs::Result describes a single arrival/departure
as obtained by Travel::Status::DE::IRIS.  It contains information about
the platform, time, route and more.

=head1 METHODS

=head2 ACCESSORS

=over

=item $result->additional_stops

Returns served stops which are not part of the schedule. I.e., this is the
set of actual stops (B<route_post>) minus the set of scheduled stops
(B<sched_route_post>).

=item $result->arrival

DateTime(3pm) object for the arrival date and time. undef if the
train starts here. Contains realtime data if available.

=item $result->arrival_delay

Estimated arrival delay in minutes (integer number). undef if no realtime
data is available, the train starts at the specified station, or there is
no scheduled arrival time (e.g. due to diversions). May be negative.

=item $result->arrival_has_realtime

True if "arrival" is based on real-time data.

=item $result->arrival_hidden

True if arrival should not be displayed to customers.
This often indicates an entry-only stop near the beginning of a train's journey.

=item $result->arrival_is_additional

True if the arrival at this stop is an additional (unscheduled) event, i.e.,
if the train started its journey earlier than planned.

=item $result->arrival_is_cancelled

True if the arrival at this stop has been cancelled.

=item $result->arrival_wings

Returns a list of weakened references to Travel::Status::DE::IRIS::Result(3pm)
objects which are coupled to this train on arrival. Returns nothing (false /
empty list) otherwise.

=item $result->canceled_stops

Returns stops which are scheduled, but will not be served by this train.
I.e., this is the set of scheduled stops (B<sched_route_post>) minus the set of
actual stops (B<route_post>).

=item $result->classes

List of characters indicating the class(es) of this train, may be empty. This
is slighty related to B<type>, but more generic. At this time, the following
classes are known:

    D    Non-DB train. Usually local transport
    D,F  Non-DB train, long distance transport
    F    "Fernverkehr", long-distance transport
    N    "Nahverkehr", local and regional transport
    S    S-Bahn, rather slow local/regional transport

=item $result->date

Scheduled departure date if available, arrival date otherwise (e.g. if the
train ends here). String in dd.mm.YYYY format. Does not contain realtime data.

=item $result->datetime

DateTime(3pm) object for departure if available, arrival otherwise. Does not
contain realtime data.

=item $result->delay

Estimated delay in minutes (integer number). Defaults to the departure delay,
except for trains which terminate at the specifed station. Similar to
C<< $result->departure_delay // $result->arrival_delay >>. undef if
no realtime data is available. May be negative.

=item $result->delay_messages

Get all delay messages entered for this train. Returns a list of [datetime,
string] listrefs sorted by newest first. The datetime part is a DateTime(3pm)
object corresponding to the point in time when the message was entered, the
string is the message. If a delay reason was entered more than once, only its
most recent record will be returned.

=item $result->departure

DateTime(3pm) object for the departure date and time. undef if the train ends
here. Contains realtime data if available.

=item $result->departure_delay

Estimated departure delay in minutes (integer number). undef if no realtime
data is available, the train terminates at the specified station, or there is
no scheduled departure time (e.g. due to diversions). May be negative.

=item $result->departure_has_realtime

True if "departure" is based on real-time data.

=item $result->departure_hidden

True if departure should not be displayed to customers.
This often indicates an exit-only stop near the end of a train's journey.

=item $result->departure_is_additional

True if the train's departure at this stop is unscheduled (additional), i.e.,
the route has been extended past its scheduled terminal stop.

=item $result->departure_is_cancelled

True if the train's departure at this stop has been cancelled, i.e., the train
terminates here and does not continue its scheduled journey.

=item $result->departure_wings

Returns a list of weakened references to Travel::Status::DE::IRIS::Result(3pm)
objects which are coupled to this train on departure. Returns nothing (false /
empty list) otherwise.

=item $result->destination

Alias for route_end.

=item $result->has_realtime

True if arrival or departure time are based on real-time data. Note that this
is different from C<< defined($esult->delay) >>. If delay is defined, some kind
of realtime information for the train is available, but not necessarily its
arrival/departure time. If has_realtime is true, arrival/departure time are
available. This behaviour may change in the future.

=item $result->info

List of information strings. Contains both reasons for delays (which may or
may not be up-to-date) and generic information such as missing carriages or
broken toilets.

=item $result->is_additional

True if the train's arrival and departure at the stop are unscheduled
additional stops, false otherwise.

=item $result->is_cancelled

True if the train was cancelled, false otherwise. Note that this does not
contain information about replacement trains or route diversions.

=item $result->is_transfer

True if the train changes its ID at the current station, false otherwise.

An ID change means: There are two results in the system (e.g. RE 10228
ME<uuml>nster -> Duisburg, RE 30028 Duisburg -> DE<uuml>sseldorf), but they are
the same train (RE line 2 from ME<uuml>nster to DE<uuml>sseldorf in this case)
and should be treated as such. In this case, Travel::Status::DE::IRIS merges
the results and indicates it by setting B<is_transfer> to a true value.

In case of a transfer, B<train_id> and B<train_no> are set to the "new"
value, the old ones are available in B<old_train_id> and B<old_train_no>.

=item $result->is_unscheduled

True if the train does not appear in the requested plans. This can happen
because of two reasons: Either the scheduled time and the actual time are so
far apart that it should've arrived/departed long ago, or it really is an
unscheduled train. In that case, it can be a replacement or an additional
train. There is no logic to distinguish these cases yet.

=item $result->is_wing

Returns true if this result is a wing, false otherwise.
A wing is a train which has its own ID and destination, but is currently
coupled to another train and shares all or some of its route.

=item $result->line

Train type with line (such as C<< S 1 >>) if available, type with number
(suc as C<< RE 10126 >>) otherwise.

=item $result->line_no

Number of the line, undef if unknown. Seems to be set only for S-Bahn and
regional trains. Note that some regional and most long-distance trains do
not have this field set, even if they have a common line number.

Example: For the line C<< S 1 >>, line_no will return C<< 1 >>.

=item $result->messages

Get all qos and delay messages ever entered for this train. Returns a list of
[datetime, string] listrefs sorted by newest first. The datetime part is a
DateTime(3pm) object corresponding to the point in time when the message was
entered, the string is the message. Note that neither duplicates nor superseded
messages are filtered from this list.

=item $result->old_train_id

Numeric ID of the pre-transfer train. Seems to be unique for a year and
trackable across stations. Only defined if a transfer took place,
see also B<is_transfer>.

=item $result->old_train_no

Number of the pre-tarnsfer train, unique per day. E.g. C<< 2225 >> for
C<< IC 2225 >>. Only defined if a transfer took
place, see also B<is_transfer>.

=item $result->origin

Alias for route_start.

=item $result->qos_messages

Get all current qos messages for this train. Returns a list of [datetime,
string] listrefs sorted by newest first. The datetime part is a DateTime(3pm)
object corresponding to the point in time when the message was entered, the
string is the message. Contains neither superseded messages nor duplicates (in
case of a duplicate, only the most recent message is present)

=item $result->platform

Arrival/departure platform as string, undef if unknown. Note that this is
not neccessarily a number, platform sections may be included (e.g.
C<< 3a/b >>).

=item $result->raw_id

Raw ID of the departure, e.g. C<< -4642102742373784975-1401031322-6 >>.
The first part appears to be this train's UUID (can be tracked across
multiple stations), the second the YYmmddHHMM departure timestamp at its
start station, and the third the count of this station in the train's schedule
(in this case, it's the sixth from thestart station).

About half of all departure IDs do not contain the leading minus (C<< - >>)
seen in this example. The reason for this is unknown.

This is a developer option. It may be removed without prior warning.

=item $result->realtime_xml

XML::LibXML::Node(3pm) object containing all realtime data. undef if none is
available.

This is a developer option. It may be removed without prior warning.

=item $result->replaced_by

Returns a list of weakened references to Travel::Status::DE::IRIS::Result(3pm)
objects which replace the (usually cancelled) arrival/departure of this train.
Returns nothing (false / empty list) otherwise.

=item $result->replacement_for

Returns a list of weakened references to Travel::Status::DE::IRIS::Result(3pm)
objects which this (usually unplanned) train is meant to replace.  Returns
nothing (false / empty list) otherwise.

=item $result->route

List of all stations served by this train, according to its schedule. Does
not contain realtime data.

=item $result->route_end

Name of the last station served by this train.

=item $result->route_interesting

List of up to three "interesting" stations served by this train, subset of
route_post. Usually contains the next stop and one or two major stations after
that. Does not contain realtime data.

=item $result->route_pre

List of station names the train passed (or will have passed) before this stop.

=item $result->route_post

List of station names the train will pass after this stop.

=item $result->route_start

Name of the first station served by this train.

=item $result->sched_arrival

DateTime(3pm) object for the scheduled arrival date and time. undef if the
train starts here.

=item $result->sched_departure

DateTime(3pm) object for the scheduled departure date and time. undef if the
train ends here.

=item $result->sched_platform

Scheduled Arrival/departure platform as string, undef if unknown. Note that
this is not neccessarily a number, platform sections may be included (e.g.  C<<
3a/b >>).

=item $result->sched_route

List of all stations served by this train, according to its schedule. Does
not contain realtime data.

=item $result->sched_route_end

Name of the last station served by this train according to its schedule.

=item $result->sched_route_pre

List of station names the train is scheduled to pass before this stop.

=item $result->sched_route_post

List of station names the train is scheduled to pass after this stop.

=item $result->sched_route_start

Name of the first station served by this train according to its schedule.

=item $result->start

DateTime(3pm) object for the scheduled start of the train on its route
(i.e. the departure time at its first station).

=item $result->station

Name of the station this train result belongs to.

=item $result->station_eva

EVA number of the station this train result belongs to.
This is often, but not always, identical with the UIC station number.

=item $result->stop_no

Number of this stop on the train's route. 1 if it's the start station, 2
for the stop after that, and so on.

=item $result->time

Scheduled departure time if available, arrival time otherwise (e.g. if the
train ends here). String in HH:MM format. Does not contain realtime data.

=item $result->train

Alias for line.

=item $result->train_id

Numeric ID of this train, trackable across stations and days. For instance, the
S 31128 (S1) to Solingen, starting in Dortmund on 19:23, has the ID
2404170432985554630 on each station it passes and (usually) on every day of the
year.  Note that it may change during the yearly itinerary update in december.

=item $result->train_no

Number of this train, unique per day. E.g. C<< 2225 >> for C<< IC 2225 >>.

=item $result->type

Type of this train, e.g. C<< S >> for S-Bahn, C<< RE >> for Regional-Express,
C<< ICE >> for InterCity-Express.

=item $result->wing_of

If B<is_wing> is true, returns a weakened reference to the
Travel::Status::DE::IRIS::Result(3pm) object which this train is a wing of. So
far, it seems that a train is either not a wing or a wing of exactly one other
train. Returns undef if B<is_wing> is false.

=back

=head2 INTERNAL

=over

=item $result = Travel::Status::DE::IRIS::Result->new(I<%data>)

Returns a new Travel::Status::DE::IRIS::Result object.
You usually do not need to call this.

=back

=head1 DIAGNOSTICS

None.

=head1 DEPENDENCIES

=over

=item Class::Accessor(3pm)

=back

=head1 BUGS AND LIMITATIONS

Unknown.

=head1 SEE ALSO

Travel::Status::DE::IRIS(3pm).

=head1 AUTHOR

Copyright (C) 2013-2024 by Birte Kristina Friesel E<lt>derf@finalrewind.orgE<gt>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.
