#! /usr/bin/perl -w

$\="\n";


use strict;
use utf8;
use Fcntl qw(:DEFAULT :flock);
use Benchmark;
use Time::HiRes();


my $t0 = new Benchmark;

our %month_name;
@month_name{qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)} = (1..12);


my ($file_name, $start_time, $end_time, $message_prop);

# guess WHO is WHO 
foreach(@ARGV) {
if (m@^[-a-z0-9!#$%&'*+/=?^_`{|}~]+(?:\.[-a-z0-9!#$%&'*+/=?^_`{|}~]+)*\@(?:[a-z0-9](?:[-a-z0-9]*[a-z0-9])?\.)+(?:[a-z]{2}|com|org|net|gov|mil|biz|info|mobi|name|aero|jobs|museum)$@i) 
	{$message_prop = $_ ;}
elsif(m@((?:\d{2}){0,2}T(?:\d{2}){0,3})?/((?:\d{2}){0,2}T(?:\d{2}){0,3})?@) 
	{($start_time, $end_time)=($1,$2);}
elsif(!$file_name){$file_name=$_;}
}

&error unless ($message_prop&&$file_name);

#Apr 26 00:00:00 - MTA timestamp format
my $re = qr/^([JFMASOND]\w{2})\s(\d{2})\s(\d{2}):(\d{2}):(\d{2})/;
my %row_index;

unless (-f $file_name) {print "No file [$file_name]" ; exit 0};
my $file_size = -s $file_name;

open (FH, "<", $file_name) or die "Can't open filename: $!" ;
flock(FH, 1) or die "Can't lock filename: $!";
# make "row" index time-file_shift
my $file_ok;
while (<FH>) {
	if (/$re/) {
	$file_ok = 0;
	my $log_date = sprintf ("%02u%02u%02u%02u%02u",$month_name{$1},$2,$3,$4,$5);
	$start_time = ($log_date =~ /(\d{4})/)[0].'T' if(!$start_time);
	my $tell;
	{use bytes;$tell = (tell FH) -  length($_);}
	$row_index{$log_date}=$tell;
	seek(FH,(int ($file_size/24)),1);
	next;
	} else { # die if Can`t find date on more than 3 row - its not log
	if (++$file_ok>4) {print "Wrong date format or not log file [$file_name]";exit 0}
	}
}


if(!$end_time) { #just get NEXT day if NULL
	@_=split (' ',localtime(time+86400));$end_time=$month_name{$_[1]}.$_[2].'T';}


$start_time = &get_time($start_time);
$end_time = &get_time($end_time);


my $prev_key;
for my $key (sort keys %row_index) {
	last if ($key gt $start_time); 
	$prev_key = $key;
}

# go to nearest to START LOWER file_shift block , or just to BEGIN of file
my $pitch = $prev_key ? $row_index{$prev_key} : 0;
seek(FH,$pitch,0);

$re = qr/]:\s([0-9A-F]{11}):\s.+?=<\Q$message_prop\E>/o; # yes, I use saving curves. It`s OK :)

my ($tell, $MTA_ID,@parent_accum,$pid,$child_stop); 

while (<FH>) {

my @log_date = unpack ("A3xA2xA2xA2xA2",$_);
my $log_date = sprintf ("%02u%02u%02u%02u%02u",$month_name{$log_date[0]},@log_date[1..4]);

next if ($log_date lt $start_time);
last if ($log_date gt $end_time); # I don`t WANT fix 1231T235959 -> 0101T000000 bug - too slow.


if (!defined $tell) { use bytes;
	$tell = (tell FH) -  length($_);}

# search FIRST MTA-ID for matching mail. Just re-search with START time
	if (?$re?) {	
	$re = qr/]:\s\Q$1\E:\s/o;
	$MTA_ID = 1;
	{ use bytes;
	$child_stop = (tell FH) -  length($_);
	}
		$pid = fork();
		die "Can`t fork: $!" unless defined $pid;
		if ($pid == 0) { #make fork for second pass to find earlier match
				
		my $child_line_numb;
		open (FH2, "<", $file_name) or die "Can't open filename: $!" ;
		flock(FH2, 1) or die "Can't lock filename: $!";
		seek(FH2,$tell,0);
		
			while (<FH2>) {
				
				last if (tell FH2 > $child_stop );
				
				if (/$re/) {
				chomp;print $_;
				}
			}
		close FH2;
		exit 0;
		}
	

	} 

	if ($MTA_ID && /$re/) {
	chomp;
	push (@parent_accum , $_);
	}

}

close FH;


exit unless defined $parent_accum[0]; #  just exit if void result (as find)


waitpid($pid,0); # race bug resolve

foreach (@parent_accum) {print} # it`s good for huge list AND not bad for small

my  $t1 = new Benchmark;
print "\nFind in".timestr(timediff($t1, $t0));

1;

sub get_time {

my ($month,$day);
our %month_name;
my (undef, $reserv_month, $reserv_day) = split (' ',localtime(time)); # Nov 12 
  

my @date_time = split ('T', shift||'T');

if ($date_time[1] && $date_time[1] !~ /^(\d\d){0,3}$/) {die "wrong time format! [".$date_time[1]."]";}
$date_time[1] .= 0 x (6 - ($date_time[1]?length ($date_time[1]):0));# date OK

if ($date_time[0] && length $date_time[0] >= 2) {
	$day = substr $date_time[0],-2;
	if (length $date_time[0] >= 4) {
		$month = substr $date_time[0],-4,2;
		}
		else {
		$month = $month_name{$reserv_month};
		}	
	}
	else {	
	($month,$day) = ($month_name{$reserv_month}, $reserv_day);
	}

return ("$month$day$date_time[1]");
}

sub error {
(my $text = <<EOF) =~ s/^\s+//gm;
	Not enough ARG! Script call as
	mta_log.pl [START]/[END] MESSAGE-ID|ADDRESS FILE.LOG
	~ where START and END optional time
	time format [[[[[cc]yy]mm]dd]T[hh[mm[ss]]]]
	~ where MESSAGE-ID|ADDRESS is MESSAGE-ID or "from" or "to" ADDRESS
	~ where FILE.LOG is name of MTA file log
EOF
die "$text";
}

__END__

=encoding utf-8

=pod

=head1 NAME

Обработка лог файлов.

=head1 VERSION

B<$VERSION 0.3.1>

=head1 SYNOPSIS

Вызывается с аргументами - [START]/[END] MESSAGE-ID|ADDRESS FILE.LOG
	mta_log.pl [START]/[END] MESSAGE-ID|ADDRESS FILE.LOG
	
	mta_log.pl / ya@ya.ru maillog.log

=head1 DESCRIPTION

Скрипт может отслеживать обработку определенного письма внутри MTA
по сообщениям в log файле. Скрипту передается временной интервал,
в котором надо искать сообщения, и, либо message-id сообщения,
либо адрес from или to сообщения. Скрипт должен определить
уникальный ID первого сообщения, присвоенный ему MTA и вывести ВСЕ
записи из лог файла в заданном временном промежутке, относящиеся к
данному ID. В случае, когда указан адрес from или to сообщения, и
в указанном промежутке времени есть несколько сообщений с
заданными адресами, нужно выводить записи из лог файла, только для
первого сообщения.

Скрипт может быть вызван как:
	mta_log.pl [START]/[END] MESSAGE-ID|ADDRESS FILE.LOG

START и END - это соотвественно начальное и конечное время, внутри
которого требуется производить обработку. Время задается в ISO
8601 restricted time format (см. прим. 1).

MESSAGE-ID - это ID сообщения.

ADDRESS - это from или to email адрес

FILE.LOG - имя файла, в котором осуществляем поиск.
 
Примечание 1.
 
    ISO 8601 restricted time format
 
    The lead-in character for a restricted ISO 8601 time is an
    `@'-sign.  The particular format of the time in restricted ISO
    8601 is: [[[[[cc]yy]mm]dd][T[hh[mm[ss]]]]].  Optional date fields
    default to the appropriate component of the current date; option-
    al time fields default to midnight; hence if today is January 22,
    1999, the following date specifications are all equivalent:
 
    `19990122T000000'
    `990122T000000'
    `0122T000000'
    `22T000000'
    `T000000'
    `T0000'
    `T00'
    `22T'
    `T'
    `'

=head1 AUTOR	

Meettya <L<meettya@gmail.com>>

=head1 BUGS

1. Не учтен переход через Новый Год 1231T235959 -> 0101T000000 ни в логе ни при вызове скрипта
2. Не реализован интерфейс с ключами аргументов для однозначной интерпретации аргументов вызова.

=head1 SEE ALSO

=head1 CHANGELOG

VERSION 0.3.1 - добавлено автодополнение даты, дату можно указать пустым слешом '/' что означает от начала файла до ЗАВТРА. Этого вполне хватит для поиска по всему файлу.

VERSION 0.2.1 - добавлен "грязный" индекс для ускорения поиска начала временной границы

VERSION 0.1.1 - поиск возможных совпадений до момента определения MTA_ID вынесен в отдельный поток для ускорения процесса.

=head1 COPYRIGHT

B<Moscow>, fall 2009.

=cut