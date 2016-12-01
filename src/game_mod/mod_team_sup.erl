%%%----------------------------------------------------------------------
%%% @copyright 2010 mgee (Ming Game Engine Erlang)
%%%
%%% @author odinxu, 2010-1-19
%%% @doc team supervisor, every team is a gen_server, on the mod_team_sup.
%%% @end
%%%----------------------------------------------------------------------

-module(mod_team_sup).

-behaviour(supervisor).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------

%% --------------------------------------------------------------------
%% External exports
%% --------------------------------------------------------------------
-export([]).

%% --------------------------------------------------------------------
%% Internal exports
%% --------------------------------------------------------------------
-export([
		 start_link/0,
		 init/1
        ]).

%% --------------------------------------------------------------------
%% Macros
%% --------------------------------------------------------------------


%% --------------------------------------------------------------------
%% Records
%% --------------------------------------------------------------------

%% ====================================================================
%% External functions
%% ====================================================================


start_link() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ====================================================================
%% Server functions
%% ====================================================================
%% --------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok,  {SupFlags,  [ChildSpec]}} |
%%          ignore                          |
%%          {error, Reason}
%% --------------------------------------------------------------------
init([]) ->
    {ok,{{simple_one_for_one,10,10}, 
		 [{mod_team, 
		   {mod_team, start_link, []}, 
		   transient, brutal_kill, worker, [mod_team]}
		  ]}}.

%% ====================================================================
%% Internal functions
%% ====================================================================

