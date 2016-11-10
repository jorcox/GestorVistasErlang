%% AUTOR: Javier Beltran Jorba, Jorge Cancer Gil
%% NIP: 532581, 646122
%% FICHERO: scv.erl
%% TIEMPO: 6 horas
%% DESCRIPCION: contiene la funcionalidad de los servidores clave/valor, que pueden
%% recibir peticiones de lectura y escritura, y mandan latidos periodicos al gestor de vistas.

-module(scv).
-export([init_scv/2,latidos/4,servidor/6]).


init_scv(Id,NodoSv) ->
	servidor({servidor_vistas, NodoSv}, 0, Id, dict:new(), self(), 0).

init_lat(Sv, Id, Pid_servidor) ->
	io:format("Enviado latido inicial... -> ~B~n", [Id]),
	%erlang:send_after(100, Sv, {latido, 0, Pid_servidor, Id}),
	Sv ! {latido, 0, Pid_servidor, Id},
	receive
		{N, Primario} ->
			io:format("Recibida primera respuesta -> ~B~n", [Id]),
			%io:format("Vista actualizada ~n"),
			%io:format("Vista actualizada ~B~n", [VistaNueva]),
			self() ! {N, Primario};
		{N, Primario, Backup} ->
			io:format("Recibida primera respuesta -> ~B~n", [Id]),
			self() ! {N, Primario, Backup}
	end,
	spawn(scv, latidos, [Sv, N, Id, self()]).


latidos(Sv, NumVista, Id, Pid_servidor) ->
	%io:format("Latedor lanzado ~n"),
	%io:format("Enviando latido ~B~n", [NumVista]),
	%erlang:send_after(100, Sv, {latido, NumVista, Pid_servidor, Id}),
	timer:sleep(100),
	Sv ! {latido, NumVista, Pid_servidor, Id},
	receive
		{VistaNueva} ->
			%io:format("Vista actualizada ~n"),
			%io:format("Vista actualizada ~B~n", [VistaNueva]),
			VistaNueva
	after 10 ->
		VistaNueva = NumVista
	end,
	latidos(Sv, VistaNueva, Id, Pid_servidor).

servidor(Sv, Rol, Id, Dict, Lat, NumVista) ->
	if
		Rol == 0 ->		%Si esta recien lanzado, manda Latido 0
			io:format("Lanzando emisor de latidos ~n"),
			%io:format("Lanzando latedor ~p ~n",[Lat]),
			%Lata = spawn(scv, latidos, [Sv, 0, Id, self()]);	%Se crea el proceso que controla los latidos	
			Lata = init_lat(Sv, Id, self()),
			link(Lata);
		true ->
			Lata = Lat
	end,
	receive
		{escribir, Clave, NuevoValor, Pid} ->
			Sv ! {backup_propuesto, self()},
			receive 
				{no_BU}->
					Pid ! {eError},
					servidor(Sv, Rol, Id, Dict, Lata, NumVista);
				{BU} ->
					io:format("BU recibido ~n"),
					BU ! {respaldoE, Clave, NuevoValor, self()}
			end,
			receive
				{ok_escritura} ->
					io:format("Recibida confirmacion del BackUp ~n"),
					DictAux = dict:store(Clave, NuevoValor, Dict),
					Pid ! {eRealizada},
					servidor(Sv, Rol, Id, DictAux, Lata, NumVista)
			after 100 ->
				Pid ! {eError},
				servidor(Sv, Rol, Id, Dict, Lata, NumVista)
			end;

		{escribirHash, Clave, NuevoValor, Pid} ->
			Sv ! {backup_propuesto, self()},
			receive 
				{no_BU}->
					Pid ! {eHError},
					servidor(Sv, Rol, Id, Dict, Lata, NumVista);
				{BU} ->
					io:format("BU recibido ~n"),
					BU ! {respaldoEH, Clave, NuevoValor, self()}
			end,
			receive
				{ok_escrituraHash} ->
					io:format("Recibida confirmacion del BackUp ~n"),
					Result = dict:find(Clave, Dict),
					if
						Result == error ->
							L = [Result, NuevoValor];
						true ->
							L = [element(2, Result), NuevoValor]
					end,
					Hash = erlang:hash(L, 999999),
					DictAux = dict:store(Clave, Hash, Dict),
					Pid ! {eHRealizada, lists:nth(1, L)},
					servidor(Sv, Rol, Id, DictAux, Lata, NumVista)
			after 100 ->
				Pid ! {eHError},
				servidor(Sv, Rol, Id, Dict, Lata, NumVista)
			end;

		{lee, Clave, Pid} ->			%Peticiones de lectura de clientes
			Sv ! {backup_propuesto, self()},
			receive 
				{no_BU}->
					Pid ! {lError},
					servidor(Sv, Rol, Id, Dict, Lata, NumVista);
				{BU} ->
					io:format("BU recibido ~n"),
					BU ! {respaldoL, Clave, self()}
			end,
			receive
				{ok_lectura, _Resul} ->
					io:format("Recibida confirmacion del BackUp ~n"),
					Result = dict:find(Clave, Dict),
					if
						Result == error ->
							Pid ! {lError},
							servidor(Sv, Rol, Id, Dict, Lata, NumVista);
						true ->
							Pid ! {element(2, Result)},
							servidor(Sv, Rol, Id, Dict, Lata, NumVista)
					end
			after 100 ->
				Pid ! {lError},
				servidor(Sv, Rol, Id, Dict, Lata, NumVista)
			end;	

		{respaldoL, Clave, PidP} ->		%Peticiones de respaldo de primarios
			if
				Rol == 2 ->
					Resul = dict:find(Clave, Dict),
					if
						Resul == error ->
							PidP ! {ok_lectura, error},
							servidor(Sv, Rol, Id, Dict, Lata, NumVista);
						true ->
							PidP ! {ok_lectura, element(2, Resul)},
							servidor(Sv, Rol, Id, Dict, Lata, NumVista)
					end
			end;

		{respaldoE, Clave, NuevoValor, PidP} ->		%Peticiones de respaldo de primarios
			io:format("Procesando respaldo ~B ~n", [Rol]),
			if
				Rol == 2 ->
					DictAux = dict:store(Clave, NuevoValor, Dict),
					PidP ! {ok_escritura},
					servidor(Sv, Rol, Id, DictAux, Lata, NumVista)
			end;
		
		{respaldoEH, Clave, NuevoValor, PidP} ->		%Peticiones de respaldo de primarios
			io:format("Procesando respaldo ~B ~n", [Rol]),
			if
				Rol == 2 ->
					Result = dict:find(Clave, Dict),
					if
						Result == error ->
							L = [Result, NuevoValor];
						true ->
							L = [element(2, Result), NuevoValor]
					end,
					Hash = erlang:hash(L, 999999),
					DictAux = dict:store(Clave, Hash, Dict),
					PidP ! {ok_escrituraHash},
					servidor(Sv, Rol, Id, DictAux, Lata, NumVista)
			end;
			
		{replicacion, Dicto, Pid} ->
			%timer:sleep(1000),
			Pid ! {ok_replicacion},
			servidor(Sv, Rol, Id, Dicto, Lata, NumVista);

		{N, Primario} ->		%Es la primera vista asi que le toca ser primario
			if
				Primario == Id ->	%Realmente siempre va a ser cierto
					Lata ! {N},
					servidor(Sv, 1, Id, Dict, Lata, NumVista);
				true ->		%No va a llegar aqui
					servidor(Sv, 3, Id, Dict, Lata, NumVista)
			end;
		{N, Primario, Backup} ->		%No es la primera vista asi que comprueba lo que le toca ser
			if
				N /= NumVista, Primario == Id ->
					replicar(Dict, Sv),
					Lata ! {N},
					servidor(Sv, 1, Id, Dict, Lata, N);
				Primario == Id ->
					Lata ! {N},
					servidor(Sv, 1, Id, Dict, Lata, N);
				Backup == Id ->
					Lata ! {N},
					servidor(Sv, 2, Id, Dict, Lata, N);
				true ->
					Lata ! {N},
					servidor(Sv, 3, Id, Dict, Lata, N)
			end
	end.

vista_valida(Sv) ->
	Sv ! {vista, self()},
	receive 
		{{NV, PV, BV}, Bool} ->
			{{NV, PV, BV}, Bool}
	end.

replicar(Dict, Sv) ->
	io:format("Iniciando replicacion ~n"),
	Sv ! {backup_propuesto, self()},
	receive 
		{no_BU}->
			io:format("No hay backup para replicarse ~n");
		{BU} ->
			io:format("BU recibido ~n"),
			BU ! {replicacion, Dict, self()},
			espera_replicacion()
	end.

espera_replicacion() ->
	receive
		{ok_replicacion} ->
			io:format("Replicación completada ~n"),
			ok;
		{escribir, _, _, Pid} ->
			Pid ! {eError},
			espera_replicacion();
		{lee, _, Pid} ->
			Pid ! {lError},
			espera_replicacion()
	end.

