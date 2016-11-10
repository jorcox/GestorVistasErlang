%% AUTOR: Javier Beltran Jorba, Jorge Cancer Gil
%% NIP: 532581, 646122
%% FICHERO: sv.erl
%% TIEMPO: 10 horas
%% DESCRIPCION: contiene la funcionalidad del gestor de vistas y controla la llegada
%% de los latidos de los demas servidores.

-module(sv).
-export([init_gestor/0, proc_timeout/3, gestor_vistas/4, buscar_backup/2]).
-define(ITR, 5).
-define(TIEMPO, 150).


init_gestor() ->
	register(servidor_vistas, self()),
	gestor_vistas({0,0,0},{0,0,0},dict:new(),dict:new()).

proc_timeout(Pid_Gestor, Id, 0) ->
	Pid_Gestor ! {timeout, Id};		%5 latidos no recibidos, envia aviso

proc_timeout(Pid_Gestor, Id, N) ->
	receive
		{ack} -> proc_timeout (Pid_Gestor, Id, ?ITR)		%Ha llegado un latido, reiniciar contador
	after ?TIEMPO ->
		io:format("Sin latido de ~B, intentando Timeout ~B~n", [Id,N-1]),
		proc_timeout(Pid_Gestor, Id, N-1)		%No ha llegado un latido, decrementar contador
	end.


buscar_backup(Dict, BVP) ->
	io:format("Buscando backup del proceso... ~p~n", [self()]),
	Vivos = dict:filter(fun(_, {V, _}) -> (V == 1) end, Dict),	%Saco un diccionario con los servidores vivos
	List = dict:to_list(Vivos),									%La convierto a lista
	io:format("Hay ~B servidores activos.~n", [length(List)]),
	if
		length(List) > 1 ->
			{Candidato, {_, _}} = lists:nth(1,List),	%Obtengo al primer candidato
			if 
				Candidato /= BVP ->			%Si el candidato no es el mismo que el backup, es adecuado
					io:format("~B pasa a ser backup.~n", [Candidato]),
					Candidato;
				true ->			%Si el candidato es el mismo que backup, coger otro
					element(1,lists:nth(2,List))
			end;
		true ->
			io:format("No hay servidores en espera.~n", []),
			0
	end.

actualizar(Dict, Id, Pid) ->
	Servidor = dict:find(Id, Dict),
	if
		Servidor == error ->					%Si el servidor no estaba registrado, lo registra.
			dict:store(Id, {1, Pid}, Dict);
		true ->								%Si el servidor ya esta registrado, lo vuelve a poner como vivo.
			io:format("El servidor ~B ha rearrancado~n", [Id]),
			dict:store(Id, {1, Pid}, Dict)
			%dict:update(Id, fun({K, _}) -> {1, Pid}, end, Dict)
	end.	
	
gestor_vistas({NVV, PVV, BVV}, {NVP, PVP, BVP}, Dict_Time, Dict_State) ->
	%io:format("Vista valida actual: ~B ~B ~B ~p~n", [NVV, PVV, BVV, self()]),
	receive	
		{vista, Pid} ->		%Peticion de vista
			if
				PVV /= 0 ->
					A = element(2, element(2,dict:find(PVV, Dict_State))),
					Res = true;
				true -> 
					A = 0,
					Res = false
			end,
			if
				BVV /= 0 ->
					B = element(2, element(2,dict:find(BVV, Dict_State))),
					Res = true;
				true -> 
					B = 0,
					Res = false
			end,
			io:format("Vista a enviar ~B ~p ~p ~n", [NVV, A, B]),
			%Pid ! {{NVV, element(2, element(2,dict:find(PVV, Dict_State))), element(2, element(2,dict:find(BVV, Dict_State)))}, true},
			Pid ! {{NVV, A, B}, Res},
			gestor_vistas({NVV, PVV, BVV}, {NVP, PVP, BVP}, Dict_Time, Dict_State);	
		{primario, Pid} ->
			io:format("Recibida peticion de conocer primario, que es: ~B ~n", [PVV]),
			Pid ! {element(2, element(2,dict:find(PVP, Dict_State)))},
			gestor_vistas({NVV, PVV, BVV}, {NVP, PVP, BVP}, Dict_Time, Dict_State);	

		{backup_propuesto, Pid} ->
			if 
				BVP == 0 ->
					Pid ! {no_BU};
				true ->
					Pid ! {element(2, element(2,dict:find(BVP, Dict_State)))}
			end,
			gestor_vistas({NVV, PVV, BVV}, {NVP, PVP, BVP}, Dict_Time, Dict_State);	

		{timeout,Id} ->		%Caso de timeout	
			io:format("Caido servidor ~B", [Id]),
			DictAuxState = dict:store(Id, {0, 0}, Dict_State),			%Actualiza el diccionario indicando que ha caido el servidor
			%DictAuxState = dict:update(Id, fun(_) -> 0 end,Dict_State),	%Actualiza el diccionario indicando que ha caido el servidor
			DictAuxTime = dict:erase(Id, Dict_Time),	%Elimina de la lista el proceso timeout que acaba de terminar
			if	
				%Se ha caido el primario
				Id == PVP ->
					io:format(" --> Rol: Primario ~n", []),
					io:format("~B pasa a ser primario ~n", [BVP]),				
					Id_nuevo_B = buscar_backup(DictAuxState, BVP),		%Elige un nuevo servidor backup
					io:format("Vista propuesta actual: ~B ~B ~B ~p~n", [NVP+1, BVP, Id_nuevo_B, self()]),
					gestor_vistas({NVV, PVV, BVV}, {NVP+1, BVP, Id_nuevo_B}, DictAuxTime, DictAuxState);		%El backup pasa a ser primario. Backup pasa a ser 0
				%Se ha caido el backup
				Id == BVP ->
					io:format(" --> Rol: Backup ~n", []),	
					Id_nuevo_B = buscar_backup(DictAuxState, BVP),		%Elige un nuevo servidor backup
					io:format("Vista propuesta actual: ~B ~B ~B ~p~n", [NVP+1, PVP, Id_nuevo_B, self()]),
					gestor_vistas({NVV, PVV, BVV}, {NVP+1, PVP, Id_nuevo_B}, DictAuxTime, DictAuxState);		%El backup pasa a ser el elegido
				%Se ha caido un servidor en espera
				true ->
					io:format(" --> Rol: Espera ~n", []),
					gestor_vistas({NVV, PVV, BVV}, {NVP, PVP, BVP}, DictAuxTime, DictAuxState)		%Las vistas no cambian
			end;
			
		{latido, 0, Pid, Id} ->		%Caso de primer latido
			io:format("Latido inicial de ~B~n", [Id]),
			if
				%Caso de inicio: no hay primario ni backup
				PVP == 0 ->
					io:format(" --> Pasa a ser: Primario ~n"),
					Pid ! {NVV+1, Id},					%Le informa de que le toca ser primario. 
					DictAuxState = actualizar(Dict_State, Id, Pid),		%Registra el servidor como vivo
					Pid_control_primario = spawn(sv, proc_timeout, [self(), Id, ?ITR]),	%Se crea el proceso que controla los timeout
					DictAuxTime = dict:store(Id, Pid_control_primario, Dict_Time),		%Registra el proceso de timeout
					io:format("Vista propuesta actual: ~B ~B ~B ~p~n", [NVP+1, Id, BVP, self()]),
					gestor_vistas({NVV+1, Id, BVV}, {NVP+1, Id, BVP}, DictAuxTime, DictAuxState);	%Hay que incrementar en 1 la vista pero no se cual de las 2 
				%Caso de inicio: hay primario pero no hay backup
				BVP == 0 ->			
					io:format(" --> Pasa a ser: Backup ~n"),				
					Pid ! {NVP, PVP, Id},				%Le informa de que le toca ser backup. No se si hay que pasarle NVV o NVP
					DictAuxState = actualizar(Dict_State, Id, Pid),		%Registra el servidor como vivo
					Pid_control_backup = spawn(sv, proc_timeout, [self(), Id, ?ITR]),	%Se crea el proceso que controla los timeout
					DictAuxTime = dict:store(Id, Pid_control_backup, Dict_Time),		%Registra el proceso de timeout
					io:format("Vista propuesta actual: ~B ~B ~B ~p~n", [NVP+1, PVP, Id, self()]),				
					gestor_vistas({NVV+1, PVV, Id}, {NVP+1, PVP, Id}, DictAuxTime, DictAuxState);	%Hay que incrementar en 1 la vista pero no se cual de las 2
				%Caso general: ya hay primario y backup
				true ->								
					io:format(" --> Pasa a ser: Espera ~n"),
					Pid ! {NVP, PVP, BVP},					%Le informa de que le toca estar en espera, informandole de la vista actual
					DictAuxState = actualizar(Dict_State, Id, Pid),	%Si estaba ya registrado, lo vuelve a poner como vivo. Sino, simplemente lo registra
					Pid_control_primario = spawn(sv, proc_timeout, [self(), Id, ?ITR]),	%Se crea el proceso que controla los timeout
					DictAuxTime = dict:store(Id, Pid_control_primario, Dict_Time),	%Registra el proceso de timeout
					io:format("Vista propuesta actual: ~B ~B ~B ~p~n", [NVP, PVP, BVP, self()]),
					gestor_vistas({NVV, PVV, BVV}, {NVP, PVP, BVP}, DictAuxTime, DictAuxState)		%Las vistas no cambian
			end;
		
		{latido, NumVista, Pid, Id} ->	%Caso latido estándar.
			%io:format("Latido standard de ~B~n", [Id]),
			if
				Pid == PVV ->
					if
						NumVista == NVP ->	%Si el primario confirma nueva vista se actualiza la vista valida
							NVV=NVP,
							PVV=PVP,
							BVV=BVP;
						true -> none
					end;
				true -> none
			end,
			Pid_control = dict:fetch(Id, Dict_Time),	%Consigo el Pid del proceso que controla sus latidos
			Pid_control ! {ack},		%Le comunico a dicho proceso que ha llegado un latido
			Pid ! {NVP, PVP, BVP},		%Le envia la vista
			gestor_vistas({NVV, PVV, BVV}, {NVP, PVP, BVP}, Dict_Time, Dict_State)	%Las vistas no cambian				
	end.	

