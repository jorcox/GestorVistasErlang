%% AUTOR: Javier Beltran Jorba, Jorge Cancer Gil
%% NIP: 532581, 646122
%% FICHERO: test.erl
%% TIEMPO: 30 minutos
%% DESCRIPCION: modulo de pruebas para validar el funcionamiento del programa en una misma maquina

-module(test).
-export([start/0,start_sv/0,start_scv/2,concurrencia/0,tras_fallo_backup/0,tras_fallo_primario/0,sin_backup/0]).

start_sv() ->
	io:format("Arrancando servidor de vistas ~n", []),	
	spawn(sv,gestor_vistas,[{0,0,0},{0,0,0},dict:new(),dict:new()]).

start_scv(Id, Gestor) ->
	spawn(scv,servidor,[Gestor, 0, Id, dict:new(), Gestor, 0]).

start() ->
	Sv = start_sv(),
	Servidor1 = start_scv(1, Sv),
	timer:sleep(300),
	_Servidor2 = start_scv(2, Sv),
	timer:sleep(2000),
	exit(Servidor1,kill),
	timer:sleep(2000),
	_Servidor1_again = start_scv(1, Sv),
	timer:sleep(100),
	_Servidor3 = start_scv(3, Sv),
	timer:sleep(2000),
	exit(_Servidor2,kill),
	timer:sleep(2000),
	_Servidor2_again = start_scv(2, Sv),
	exit(_Servidor3, kill).

concurrencia() ->
	Sv = start_sv(),
	_Servidor1 = start_scv(1, Sv),
	timer:sleep(1000),
	_Servidor2 = start_scv(2, Sv),
	timer:sleep(1000),
	cliente:escribe(1,"soy 1",Sv),
	cliente:escribe(1,"soy 2",Sv),
	cliente:lee(1,Sv).

tras_fallo_backup() ->	
	Sv = start_sv(),
	_Servidor1 = start_scv(1, Sv),
	timer:sleep(300),
	_Servidor2 = start_scv(2, Sv),
	_Servidor3 = start_scv(3, Sv),
	timer:sleep(2000),
	exit(_Servidor2,kill),
	timer:sleep(1000),
	cliente:escribe(1,"ahora no",Sv),
	timer:sleep(2000),
	cliente:escribe(1,"ahora si",Sv).

tras_fallo_primario() ->
	Sv = start_sv(),
	Servidor1 = start_scv(1, Sv),
	timer:sleep(300),
	_Servidor2 = start_scv(2, Sv),
	_Servidor3 = start_scv(3, Sv),
	timer:sleep(2000),
	exit(Servidor1,kill),
	timer:sleep(1000),
	cliente:escribe(1,"mensaje1",Sv),
	timer:sleep(2000),
	cliente:escribe(1,"mensaje2",Sv).

sin_backup() ->
	Sv = start_sv(),
	_Servidor1 = start_scv(1, Sv),
	timer:sleep(1000),
	cliente:escribe(1,"mensaje1",Sv).

