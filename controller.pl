#!/usr/bin/perl -w
use Device::SerialPort;
use Term::ReadKey;
use Time::HiRes qw (sleep);
use List::Util qw(sum); 
#use strict; 

# Set up the serial port 
# 9600, 81N on the USB ftdi driver
my $port = Device::SerialPort->new("/dev/ttyS0");
$port->databits(8);
$port->baudrate(9600);
$port->parity("none");
$port->stopbits(1);

#STATUS        Display values and status of inputs and outputs in the format:
#              AAA BBB RD CC KK K2
#              where:
#              AAA = value of Analog Input #1 in 3 hexadecimal digits (000-FFF)
#              BBB = value of Analog Input #2 in 3 hexadecimal digits (000-FFF)
#              R = status of Relays 4-1 in 1 hexadecimal digit (0-F)
#              D = status of Digital Inputs 4-1 in 1 hexadecimal digit (0-F)
#              (R is the upper nibble of the byte and D is the lower nibble)
#              CC = value of the variable INT (count) in 2 hexadecimal digits (00-FF)
#              KK = value of the variable KEY in 2 hexadecimal digits (00-FF)
#              K2 = value of the variable KEY2 in 2 hexadecimal digits (00-FF)

my $temp_setpoint =5000;  # Default so heater will not come up when first started
my $overtemp_setpoint = 1100;
my $heartbeat =  1;
my $char = "";
my $status = "000 000 00 00 00 00";
my $temp1 = "";
my $temp2 =  "";
my $digital_out = "";
my $digital_in = "";
my $flow = "";
my $pump1_lo_status = "";
my $pump1_hi_status = "";
my $pump2_on_status = "";
my $heat_on_status = "";
my $temp1_lo = 0;
my $lo_spd_request = 0;
my $hi_spd_request  = 0;
my $temp1_lo = 0; 
my @temp1_avg_array = ((1900) x 60);
my $temp1_avg = 0;
my @temp2_avg_array = ((1900) x 60);
my $temp2_avg = 0;

while (1){
    system("clear");
    
# Heartbeat
    $heartbeat =  $heartbeat +1;
    
# Status from Controller
# Poll to see if any data is coming in
    $char = $port->read(255);
    $status = substr($char,52,20);
    chop($status);
    
# Map the Hex Status
    $temp1 =  substr($status, 0, 3);
    $temp2 =  substr($status, 4, 3);
    $digital_out =  substr($status, 8, 1);
    $digital_in =  substr($status, 9, 1);
    
# Convert the Hex status to Decimal or Binary
    $temp1 = sprintf("%d", hex($temp1));
    $temp2 = sprintf("%d", hex($temp2));
    $digital_out = sprintf("%04b", hex($digital_out));
    $digital_in = sprintf("%04b", hex($digital_in));
    
# Average the Temps for 60 samples 
    pop @temp1_avg_array;  # Remove last element
    unshift @temp1_avg_array,$temp1;
    $temp1_avg = sum(@temp1_avg_array)/60;
    
    pop @temp2_avg_array;  # Remove last element
    unshift @temp2_avg_array,$temp1;
    $temp2_avg = sum(@temp2_avg_array)/60;

# Contoller Inputs
    $flow = substr($digital_in, 3, 1);
    $flow = not $flow;
    $flow = 1;
        
# Controller Outputs
    $pump1_lo_status=substr($digital_out, 3, 1);
    $pump1_hi_status=substr($digital_out, 2, 1);
    $pump2_on_status=substr($digital_out, 1, 1);
    $heat_on_status=substr($digital_out, 0, 1);

# Make sure on low or hi cannot be requested at the same time
    if ($lo_spd_request == 1){$hi_spd_request = 0;}
    if ($hi_spd_request == 1){$lo_spd_request = 0;}
    
# Check the temp and set the flag if temp is low
    if ($temp1_avg > $temp_setpoint + 10){$temp1_lo = 1;}  # With Deadband
    if ($temp1_avg < $temp_setpoint){$temp1_lo = 0;}
    
# Over temp shutdown
    $overtemp_setpoint = 1100;
    if ($temp1_avg < $overtemp_setpoint || $temp2_avg < $overtemp_setpoint){$enable = 0;}
    
############# Heat Request Flag

    if ($temp1_lo ==1 & $enable == 1) {$heat_request = 1;} else {$heat_request = 0;}
    
############## Pump 1
    
    if ($heat_request == 1 & $lo_spd_request == 0 & $hi_spd_request == 0 & $pump1_hi_status == 0) {$pump1_lo_on = 1;}
    elsif ($lo_spd_request == 1 & $hi_spd_request == 0 & $pump1_hi_status == 0) {$pump1_lo_on = 1;}
    else {$pump1_lo_on = 0;}
    
    if ($hi_spd_request == 1 & $lo_spd_request == 0 & $pump1_lo_status == 0) {$pump1_hi_on = 1;}
    else {$pump1_hi_on = 0;}
    
############## Pump 2
    
    if ($pump1_hi_on == 1){$pump2_on = 1;}else {$pump2_on = 0;} 
    
############## Heater 
    
    if (($temp1_lo == 1) & ($flow == 1))
  {
	    if ($flow == 1)
	    {
	    if ($pump1_lo_on == 1 || $pump1_hi_on ==1)
	    {
		$heat_on = 1; 
	    }
	    else 
	    {
		$delay = $delay+1;
		if ($delay > 40000){
		    $heat_on = 0; 
		    $delay = 0;
		}
	    }
	    }
	}
    
    else 
    {
	$heat_on = 0; 
    }    

    
# If Hi and Lo try to run at same time disable
    if (($pump1_lo_on ==  1) &($pump1_hi_on ==  1)){
	$enable = 0;
    }

# If Hi and Lo try to run at same time disable
    if (($pump1_lo_status == 1) & ($pump1_hi_status ==  1)){
	$enable = 0;
    }

# If Disabled turn all outputs off
    if ($enable == 0){
	$pump1_lo_on = 0; 
	$pump1_hi_on = 0; 
	$pump2_on = 0;
	$heat_on = 0;
	$heat_request = 0;
	$lo_spd_request = 0;
	$hi_spd_request = 0;
    }
    
# Messages     
    print "\n\n";
    if ($enable == 0){print "**** DISABLED ***\n";}else{print "**** ENABLED ***\n";}
    print "\n\n";
    print "Heartbeat: $heartbeat\n";
    print "Status\t$status\n";
    print "Temperature #1 \t$temp1\n";
    print "Temperature #2 \t$temp2\n";
    print "Digital Out \t$digital_out\n";
    print "Digital In \t$digital_in\n\n";
    print "Temp Actual:  $temp1_avg\n";
    print "Temp Setpoint: $temp_setpoint\n";
    if ($flow == 1){print "Flow\t\t\tOK\n";}else{print "Flow\t\t\tLow\n";}
    if ($pump1_lo_on == 1){print "Pump 1 Low Speed\tOn\n";}else {print "Pump 1 Low Speed\tOff\n";}
    if ($pump1_hi_on == 1){print "Pump 1 High Speed\tOn\n";}else {print "Pump 1 High Speed\tOff\n";}
    if ($pump2_on == 1){print "Pump 2\t\t\tOn\n";}  else {print "Pump 2\t\t\tOff\n";} 
    if ($heat_request == 1){print "Heat Request\t\tOn\n";} else {print "Heat Request\t\tOff\n"}; 
    if ($heat_on == 1){print "Heat\t\t\tOn\n";} else {print "Heat\t\t\tOff\n"}; 
# User Selection
    print "\nMake Selection:\n";
    print "1> Enable\n";
    print "2> Setpoints\n" ;
    print "3> Speed\n" ;

# Write the Outputs to the Controller
    $relay_out = "RELAY1=". $pump1_lo_on . "\n\r"; 
#    print $relay_out;
    $port->write($relay_out);
    sleep(1);
    $relay_out = "RELAY2=". $pump1_hi_on . "\n\r"; 
#    print $relay_out;
    $port->write($relay_out);
    sleep(1);
    $relay_out = "RELAY3=". $pump2_on . "\n\r"; 
#    print $relay_out;
    $port->write($relay_out);
    sleep(1);
    $relay_out = "RELAY4=". $heat_on . "\n\r"; 
#    print $relay_out;
    $port->write($relay_out);
    sleep(1);
    $port->write("STATUS\n\r");
    
    

    ReadMode 'cbreak';
    $key = ReadKey(1);
    ReadMode 'normal';
    
# User Interface
    if ($key == 1){
	print "\nEnable System 1=Yes 0=No:  ";
	$input = <>;
	if ($input == 1){
	    print "System Is Enabled\n";
	    $enable = 1;
	}
	if ($input == 0){
	    print "System Is Disabled\n";
	    $enable = 0;
	}
	
    }
    
    if ($key == 2){
	print "\nEnter Temp Setpont:  ";
	$input = <>;
	print "\nNew Temp Setpoint = $input\n";
	$temp_setpoint = $input;
	
    }
    
    if ($key == 3){
	print "\nSelect Speed 1=High 0=Low:  ";
	$input = <>;
	
	if ($input == 1){
	    print "High Speed Selected\n";
	    $lo_spd_request = 0;
	    $hi_spd_request = 1;
	}
	if ($input == 0){
	    print "Low Speed Selected\n";
	    $lo_spd_request = 1;
	    $hi_spd_request = 0;
	}
	
    }
    
}
