%%%----------------------------------------------------------------------
%%% File    : mgee_virtual_world_router.erl
%%% Author  : Qingliang
%%% Created : 2010-1-4
%%% Description: Ming game engine erlang
%%%----------------------------------------------------------------------
-module(mgee_virtual_world_router).

%%-include("mgee.hrl").
%%-include("../include/g").
-include("mgee.hrl").
-include("game_pb.hrl").

-behaviour(gen_server).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------

-export([start/0, start_link/0, get_info/0]).

-export([
		 handle/1,
		 quit_vw/1,
		 exit_vw/1,
		 get_role_state/1,
		 get_virtual_world_name/1
		]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).



%% ====================================================================
%% External functions
%% ====================================================================

% @doc get module info
get_info() ->
	gen_server:call(?MODULE, info).

%% ====================================================================
%% Server functions
%% ====================================================================
start() ->
	{ok, _} = supervisor:start_child(
	  mgee_sup,
	  {mgee_virtual_world_sup,
	   {mgee_virtual_world_sup, start_link, []},
	   transient, infinity, supervisor, [mgee_virtual_world_sup]}),
	{ok, _} = supervisor:start_child(
	  mgee_sup,
	  {mgee_virtual_world_router,
	   {mgee_virtual_world_router, start_link, []},
	   transient, brutal_kill, worker, [mgee_virtual_world_router]}),
	ok.

%% start this server
start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], ?GEN_SERVER_OPTIONS).




handle({ClientSock, _Module, Method, Data, AccountName, Roleid, _RoleName}) ->
	case Method of
		<<"walk">> ->
			gen_server:cast(?MODULE, {walk, AccountName, Data});
		<<"enter">> ->
			gen_server:call(?MODULE,
							{enter, ClientSock, AccountName, Roleid, Data#m_vw_enter_tos.vwid})
	end,
	ok.

%% @desc quit means the client wanna to enter another vw
quit_vw(RolePid) ->
	gen_server:call(?MODULE, {quit, RolePid}).

%% @desc exit means the client has disconnected
exit_vw(RolePid) ->
	gen_server:call(?MODULE, {exit, RolePid}).


%% --------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%% --------------------------------------------------------------------
init([]) ->
	%% start a ets to save having started virtual world
	ets:new(mgee_virtual_world_list, [set, private, named_table]),
	ets:new(?ETS_IN_VW_ROLE_LIST, [set, protected, named_table]),
	ets:new(?ETS_IN_VW_MAP_DATA, [set, protected, named_table]),
	loadMapData(),
    {ok, none}.


%% --------------------------------------------------------------------
%% Function: handle_call/3
%% Description: Handling call messages
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------

handle_call({enter, ClientSock, AccountName, Roleid, VWId}, _From, State) ->
	VWProcessName = get_virtual_world_name(VWId),
	Pid = mgee_misc:get_role_pid(Roleid),
	case ets:lookup(?ETS_IN_VW_ROLE_LIST, Pid) of
		[{Pid, ClientSock, RoleState}] ->
			OldVWId = RoleState#p_game_role.vwid,
			if
				VWId =:= OldVWId ->
					NeedEnter = false;
				true ->
					OldVWName = get_virtual_world_name(OldVWId),
					quit_vw(OldVWName, Pid, AccountName),
					NeedEnter = true
			end;
		[{Pid, _, _}] ->
			ets:delete(?ETS_IN_VW_ROLE_LIST, Pid),
			RoleState = gen_server:call(mgee_misc:get_role_pid(Roleid), {role_state}),
			NeedEnter = true;
		[] ->
			RoleState = gen_server:call(mgee_misc:get_role_pid(Roleid), {role_state}),
			NeedEnter = true
	end,
	create_vw_if_not_exist(VWProcessName, VWId),
	%%���½�ɫ��״̬
	if
		NeedEnter =:= true ->
			update_role_state(Pid, ClientSock, RoleState#p_game_role{vwid=VWId}),
			enter_vw2(VWProcessName, Pid);
		true ->
			ok
	end,


	{reply, ok, State};

% @doc handle get info
handle_call( info, _From, State) ->
	Reply = { ets_all_vw, ets:info(?ETS_VW_LIST), ets:tab2list(?ETS_VW_LIST),
			  ?ETS_IN_VW_ROLE_LIST, ets:info(?ETS_IN_VW_ROLE_LIST), ets:tab2list(?ETS_IN_VW_ROLE_LIST),
			  ?ETS_IN_VW_MAP_DATA, ets:info(?ETS_IN_VW_MAP_DATA), ets:tab2list(?ETS_IN_VW_MAP_DATA)
			  },
	{reply, Reply, State};
%% @desc exit means the client has disconnected
handle_call({exit, Pid}, _From, State) ->
	?DEBUG("~p exit the virtual world", [Pid]),
	case ets:lookup(?ETS_IN_VW_ROLE_LIST, Pid) of
		[{Pid, _ClientSock, RoleState}] ->
			ets:delete(?ETS_IN_VW_ROLE_LIST, Pid),
			VWId = RoleState#p_game_role.vwid,
			VWProcessName = get_virtual_world_name(VWId),
			Roleid = RoleState#p_game_role.roleid,
			create_vw_if_not_exist(VWProcessName, VWId),
			quit_vw(VWProcessName, Pid, Roleid);
		_ -> ok
	end,
	{reply, ok, State};
%% @desc quit means the client wanna to enter another vw
handle_call({quit, Pid}, _From, State) ->
	?DEBUG("~p quit the virtual world", [Pid]),
	case ets:lookup(?ETS_IN_VW_ROLE_LIST, Pid) of
		[{Pid, _ClientSock, RoleState}] ->
			VWId = RoleState#p_game_role.vwid,
			VWProcessName = get_virtual_world_name(VWId),
			Roleid = RoleState#p_game_role.roleid,
			create_vw_if_not_exist(VWProcessName, VWId),
			quit_vw(VWProcessName, Pid, Roleid);
		_ -> ok
	end,
	{reply, ok, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%% --------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------

%% @desc update the role's position
handle_cast({walk, Roleid, Tx, Ty, _Px, _Py}, State) ->
	ClientPid = mgee_misc:get_role_pid(Roleid),
	case ets:lookup(?ETS_IN_VW_ROLE_LIST, ClientPid) of
		[{ClientPid, ClientSock, RoleState}] ->
			ets:insert(?ETS_IN_VW_ROLE_LIST,
					   {ClientPid, ClientSock, RoleState#p_game_role{x=Tx, y=Ty}});
		_ -> ok
	end,
	{noreply, State};
handle_cast({walk_path, Roleid, Tx, Ty, _Px, _Py}, State) ->
	ClientPid = mgee_misc:get_role_pid(Roleid),
	case ets:lookup(?ETS_IN_VW_ROLE_LIST, ClientPid) of
		[{ClientPid, ClientSock, RoleState}] ->
			ets:insert(?ETS_IN_VW_ROLE_LIST,
					   {ClientPid, ClientSock, RoleState#p_game_role{x=Tx, y=Ty}});
		_ -> ok
	end,
	{noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%% --------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%% --------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% --------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% --------------------------------------------------------------------
%%% Internal functions
%% --------------------------------------------------------------------
get_virtual_world_name(VMId) when is_integer(VMId) ->
	mgee_misc:list_to_atom2(lists:concat([virtual_world_, VMId])).

%% for a actor to enter a virtual world
enter_vw2(VWProcessName, Pid) ->
	%% only cast is asynchronous
	gen_server:cast(VWProcessName, {enter, Pid}),
	ok.

quit_vw(VWProcessName, Pid, Roleid) ->
	gen_server:cast(VWProcessName, {quit, Pid, Roleid}).

%% inin a virtual world
create_vw_if_not_exist(VWProcessName, VWId) ->
	case ets:lookup(?ETS_VW_LIST, VWProcessName) of
		[{VWProcessName, _VWPid}] -> ok;
		[] ->
			?INFO_MSG("create world ~p ~n", [VWProcessName]),
			case supervisor:start_child(mgee_virtual_world_sup, [{VWProcessName, VWId}]) of
				{ok, VWPid} ->
					ets:insert(?ETS_VW_LIST, {VWProcessName, VWPid}),
					VWPid;
				{error, {alreay_started, VWPid}} -> VWPid
			end
	end.

update_role_state(Pid, ClientSock, State) ->
	ets:insert(?ETS_IN_VW_ROLE_LIST, {Pid, ClientSock, State}).

get_role_state(Roleid) ->
	Pid = mgee_misc:get_role_pid(Roleid),
	case ets:lookup(?ETS_IN_VW_ROLE_LIST, Pid) of
		[{Pid, _, RoleState}] ->
			{ok, RoleState};
		other ->
			{error, not_found}
	end.


%% --------------------------------------------------------------------
%% @doc load map data from mcm file
loadMapData() ->
	{ok, ConfigPath} = application:get_env(config_path),
	MapConfigDir = ConfigPath ++ "/mcc/map/",
	ExtName = ".mcm",
	try file:list_dir(MapConfigDir) of
		{ok, FileList} ->
			lists:foreach(
				fun(FileName) ->
					case filename:extension(FileName) of
						ExtName ->
							?DEBUG("loading map file: ~p", [MapConfigDir ++ FileName]),
							loadMapDataFrom(MapConfigDir , FileName);
						_ ->
						   	ok
					end
				end, FileList);
		{error, Reason} ->
			?ERROR_MSG("VW Router loadMapData error: ~p, from dir: ~p", [Reason, MapConfigDir])
	catch
		_:_ -> ?ERROR_MSG("VW Router loadMapData error, from dir: ~p", [MapConfigDir])
	end.

loadMapDataFrom(MapConfigDir , FileName) ->
	FullFileName = MapConfigDir ++ FileName,
	{ok, S} = file:open(FullFileName, [read, binary, raw]),
	{ok, MapNameBin} = file:pread(S, 0, 32),
	MapName = string:strip( binary_to_list(MapNameBin), both, 0),
	{ok,  <<TileWidth:32>>  } = file:pread(S, 40, 4),
	{ok,  <<TileHeight:32>> } = file:pread(S, 44, 4),
	?DEBUG("load map data: ~p*~p, ~p ~p", [TileWidth, TileHeight, FullFileName, MapName]),
	if TileWidth > 0 andalso TileHeight > 0
		 ->
			{ok, DataBin } = file:pread(S, 48, TileWidth * TileHeight );
		true ->
			DataBin = <<>>
	end,
	file:close(S),

	if TileWidth > 0 andalso TileHeight > 0
		 ->
			?DEBUG("load map data: ~p*~p finish, begin resolv...", [TileWidth, TileHeight]),
			Ets = ets:new(load_map_data_titl_resolv, [set, private]),
			erlang:statistics(runtime),
			erlang:statistics(wall_clock),
			loadMapDataTileResolv(Ets, DataBin, TileWidth - 1, TileHeight - 1, 0, 0),
			{_, T1} = erlang:statistics(runtime),
			{_, T2} = erlang:statistics(wall_clock),
			Data = ets:tab2list(Ets),
			?DEBUG("Map data loaded: ~p, can walk tile count: ~p, load time: ~p (~p)",
		   			[FullFileName, length(Data), T1, T2]);
		true ->
			Data = []
	end,
	% get the file base name as mapid,  "10001.mcm" => "10001" => MAPID
	MAPID = filename:rootname(filename:basename(FileName)),
	ets:insert(?ETS_IN_VW_MAP_DATA, {MAPID, {MapName, TileWidth, TileHeight, Data}}),
	ok.

loadMapDataTileResolv(Ets, DataBin, XEnd, YEnd, X, Y) when X =:= XEnd andalso Y =:= YEnd ->
	<< Walk:8, _Bin/binary >> = DataBin,
	case Walk of
		0	->	ets:insert(Ets, { {X,Y}, true });
		_	->  ok
	end,
	ok;
loadMapDataTileResolv(Ets, DataBin, XEnd, YEnd, X, Y) when X =:= XEnd ->
	<< Walk:8, Bin/binary >> = DataBin,
	case Walk of
		0	->	ets:insert(Ets, { {X,Y}, true });
		_	->  ok
	end,
	loadMapDataTileResolv(Ets, Bin, XEnd, YEnd, 0, Y+1 );
loadMapDataTileResolv(Ets, DataBin, XEnd, YEnd, X, Y) ->
	<< Walk:8, Bin/binary >> = DataBin,
	case Walk of
		0	->	ets:insert(Ets, { {X,Y}, true });
		_	->  ok
	end,
	loadMapDataTileResolv(Ets, Bin, XEnd, YEnd, X + 1, Y ).
%% --------------------------------------------------------------------



