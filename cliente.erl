%% AUTOR: Javier Beltran Jorba, Jorge Cancer Gil
%% NIP: 532581, 646122
%% FICHERO: cliente.erl
%% TIEMPO: 1 hora
%% DESCRIPCION: contiene la funcionalidad de los clientes, que envian
%% peticiones de lectura o escritura.

-module(cliente).
-export([vista_valida/1, primario/1, lee/2, escribe/3, escribe_hash/3]).


vista_valida(Sv) ->
	Sv ! {vista, self()},
	receive 
		{{NV, PV, BV}, Bool} ->
			{{NV, PV, BV}, Bool}
	end.

primario(Sv) ->
	Sv ! {primario, self()},
	receive 
		{Primario} ->
			Primario
	end.

lee(Clave, Sv) ->
	Prim = primario(Sv),
	Prim ! {lee, Clave, self()},
	receive
		{lError} ->
			io:format("Se ha producido un error en la lectura ~p~n", [self()]);
		{Valor} ->
			io:format("Leido valor ~p ~n", [self()]),
			Valor
	after 500 ->
		io:format("No se recibe respuesta a la lectura ~p~n", [self()]),
		lee(Clave, Sv)
	end.

escribe(Clave, NuevoValor, Sv) ->
	io:format("Conociendo primario ~n"),
	Prim = primario(Sv),

	io:format("Primario ~p~n", [Prim]),
	io:format("Enviando ~B ~ts ~p ~n", [Clave, NuevoValor, Sv]),
	Prim ! {escribir, Clave, NuevoValor, self() },
	receive
		{eRealizada} ->
			io:format("Escrito correctamente el valor : ~ts~p~n",[NuevoValor, self()]);
		{eError} ->
			io:format("Error en la escritura del valor : ~ts~p~n",[NuevoValor, self()])
	after 500 ->
		io:format("No se recibe respuesta a la escritura ~p~n", [self()]),
		escribe(Clave, NuevoValor, Sv)
	end.

escribe_hash(Clave, NuevoValor, Sv) ->
	io:format("Conociendo primario ~n"),
	Prim = primario(Sv),

	io:format("Primario ~p~n", [Prim]),
	io:format("Enviando Hash ~B ~s ~p ~n", [Clave, NuevoValor, Sv]),
	Prim ! {escribirHash, Clave, NuevoValor, self() },
	receive
		{eHRealizada, Antiguo} ->
			io:format("Escrito correctamente valorNuevo : hash de ~ts. Devuelto valor antiguo ~p~n",[NuevoValor, self()]),
			Antiguo;
		{eHError} ->
			io:format("Error en la escritura hash del valor : ~ts~p~n",[NuevoValor, self()])
	after 500 ->
		io:format("No se recibe respuesta a la escritura hash ~p~n", [self()]),
		escribe_hash(Clave, NuevoValor, Sv)
end.

