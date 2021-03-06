module Rex
module Post
module Meterpreter
module Extensions
module Stdapi
module Railgun
module Def

class Def_netapi32

	def self.create_dll(dll_path = 'netapi32')
		dll = DLL.new(dll_path, ApiConstants.manager)

		dll.add_function('NetUserDel', 'DWORD',[
			["PWCHAR","servername","in"],
			["PWCHAR","username","in"],
			])

		dll.add_function('NetGetJoinInformation', 'DWORD',[
			["PBLOB","lpServer","in"],
			["PDWORD","lpNameBugger","out"],
			["PDWORD","BufferType","out"]
			])
		dll.add_function('NetServerEnum', 'DWORD',[
			["PWCHAR","servername","in"],
			["DWORD","level","in"],
			["PDWORD","bufptr","out"],
			["DWORD","prefmaxlen","in"],
			["PDWORD","entriesread","out"],
			["PDWORD","totalentries","out"],
			["DWORD","servertype","in"],
			["PWCHAR","domain","in"],
			["DWORD","resume_handle","inout"]
		])
		
		dll.add_function('NetSessionEnum', 'DWORD',[
			["PWCHAR","servername","in"],
			["PWCHAR","UncClientName","in"],
			["PWCHAR","username","in"],
			["DWORD","level","in"],
			["PDWORD","bufptr","out"],
			["DWORD","prefmaxlen","in"],
			["PDWORD","entriesread","out"],
			["PDWORD","totalentries","out"],
			["DWORD","resume_handle","inout"]
		])

		return dll
	end

end

end; end; end; end; end; end; end


