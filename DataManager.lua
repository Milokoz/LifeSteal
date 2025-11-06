print("[RemoteLoader] Hello World loaded from GitHub!")

-- Exemplo de função no módulo remoto
return {
	Init = function()
		print("Hello World module running!")
	end
}
