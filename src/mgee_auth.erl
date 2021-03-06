%%%----------------------------------------------------------------------
%%% @File    : mgee_auth.erl
%%% @Author  : Qingliang
%%% @Created : 2010-01-02
%%% @Description: Ming game engine erlang
%%%----------------------------------------------------------------------

-module(mgee_auth).

%%
%% Include files
%%
-include("mgee.hrl").
-include("global_lang.hrl").
-include("game_pb.hrl").
%%
%% Exported Functions
%%
-export([auth_user/1]).

-define(AUTH_TIME_OUT, 15000).

%%
%% API Functions
%%

%% @return {passed, AccountName} |
%%         {failed, Reason}      |
%%         {error, Reason}       |
auth_user(ClientSock) ->

  ?DEBUG("auth_user..~p ~n",[ClientSock]),

	case mgee_packet:recv(ClientSock, ?AUTH_TIME_OUT) of
		{ok, {<<"login">>, Method, Data}} when Method =:= <<"flash_login">> ->

			?DEBUG("pass1 Debug..Reason : ~p ~n " ,[1]),

			AuthData = game_pb:decode_m_login_flash_login_tos(Data),
			?DEBUG("auth data ~p", [AuthData]), 
			AccountName = AuthData#m_login_flash_login_tos.account_name,
			AccountPwd = AuthData#m_login_flash_login_tos.account_pwd,
			case auth_by_user_pwd(AccountName, AccountPwd) of
				{ok, passed} -> {passed, Method, AccountName};
				{error, wrong_pwd} -> {failed, Method, ?_LANG_LOGIN_WRONG_PWD};
				{error, not_exists} -> {failed, Method, ?_LANG_ACCOUNT_NOT_EXISTS};
				Other -> 
					?ERROR_MSG("unexpected mgee_account_server:auth_account return info ~p", [Other])
			end;
		{ok, {<<"login">>, Method, _Data}} when Method =:= <<"php_login">> ->

			?DEBUG("pass2 Debug..Reason : ~p ~n " ,[1]),

			{error, php_login_not_implemented};
		{ok, Packet} -> ?ERROR_MSG("wrong auth packet ~p ", [Packet]),

			?DEBUG("pass3Debug..Reason : ~p ~n " ,[1]),

						{error, wrong_packet};
		{error, Reason} ->
			?DEBUG("pass4 Debug..Reason : ~p ~n " ,[Reason]),

			{error, Reason};
		Other -> ?ERROR_MSG("unexpected info ~p", [Other])
	end.

%%
%% Local Functions
%%
auth_by_user_pwd(_AccountName, _AccountPwd) ->
	%% http:request()
	{ok, passed}.

%% auth_by_phpticket(_AccountName, _Ticket) ->
%% 	%% md5
%% 	{ok, passed}.