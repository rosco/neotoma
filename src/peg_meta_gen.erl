-module(peg_meta_gen).
-export([transform/3]).
-author("Sean Cribbs <seancribbs@gmail.com>").

transform(rules, Node, _Index) ->
  put(neotoma_root_rule, verify_rules()),
  Rules = string:join(lists:nth(2, Node), "\n\n"),
  Rules ++ "\n";
transform(declaration_sequence, Node, _Index) ->
  FirstRule = proplists:get_value(head, Node),
  OtherRules =  [lists:last(I) || I <- proplists:get_value(tail, Node, [])],
  [FirstRule|OtherRules];
transform(declaration, [{nonterminal,Symbol}|Node], Index) ->
  add_lhs(Symbol, Index),
  "'"++Symbol++"'"++"(Input, Index) ->\n  " ++
        "p(Input, Index, '"++Symbol++"', fun(I,D) -> ("++
        lists:nth(4, Node) ++
        ")(I,D) end, fun(Node, Idx) -> transform('"++Symbol++"', Node, Idx) end).";
transform(sequence, Node, _Index) ->
  Tail = [lists:nth(2, S) || S <- proplists:get_value(tail, Node)],
  Statements = [proplists:get_value(head, Node)|Tail],
  "p_seq(["++ string:join(Statements, ", ") ++ "])";
transform(choice, Node, _Index) ->
  Tail = [lists:last(S) || S <- proplists:get_value(tail, Node)],
  Statements = [proplists:get_value(head, Node)|Tail],
  "p_choose([" ++ string:join(Statements, ", ") ++ "])";
transform(label, Node, _Index) ->
  String = lists:flatten(Node),
  lists:sublist(String, length(String)-1);
transform(labeled_sequence_primary, Node, _Index) ->
  case hd(Node) of
    [] -> lists:nth(2, Node);
    Label -> "p_label('" ++ Label ++ "', "++lists:nth(2, Node)++")"
  end;
transform(single_quoted_string, Node, Index) ->
  transform(double_quoted_string, Node, Index);
transform(double_quoted_string, Node, _Index) ->
  "p_string(\""++escape_quotes(lists:flatten(proplists:get_value(string, Node)))++"\")";
transform(character_class, Node, _Index) ->
  "p_charclass(\"[" ++ escape_quotes(lists:flatten(proplists:get_value(characters, Node))) ++ "]\")";
transform(parenthesized_expression, Node, _Index) ->
  lists:nth(3, Node);
transform(atomic, {nonterminal, Symbol}, Index) ->
  add_nt(Symbol, Index),
  "fun '" ++ Symbol ++ "'/2";
transform(primary, [Atomic, one_or_more], _Index) ->
  "p_one_or_more("++Atomic++")";
transform(primary, [Atomic, zero_or_more], _Index) ->
  "p_zero_or_more("++Atomic++")";
transform(primary, [Atomic, optional], _Index) ->
  "p_optional("++Atomic++")";
transform(primary, [assert, Atomic], _Index)->
  "p_assert("++Atomic++")";
transform(primary, [not_, Atomic], _Index) ->
  "p_not("++Atomic++")";
transform(nonterminal, Node, _Index) ->
  {nonterminal, lists:flatten(Node)};
transform(anything_symbol, _Node, _Index) ->
  "p_anything()";
transform(suffix, Node, _Index) ->
  case Node of
    "*" -> zero_or_more;
    "+" -> one_or_more;
    "?" -> optional
  end;
transform(prefix, Node, _Index) ->
  case Node of
    "&" -> assert;
    "!" -> not_
  end;
transform(Rule, Node, _Index) when is_atom(Rule) ->
   Node.

escape_quotes(String) ->
  {ok, RE} = re:compile("\""),
  re:replace(String, RE, "\\\\\"", [global, {return, list}]).

add_lhs(Symbol, Index) ->
  case get(lhs) of
    undefined ->
      put(lhs, [{Symbol,Index}]);
    L when is_list(L) ->
      put(lhs, [{Symbol,Index}|L])
  end.

add_nt(Symbol, Index) ->
  case get(nts) of
    undefined ->
      put(nts, [{Symbol,Index}]);
    L when is_list(L) ->
      case proplists:is_defined(Symbol, L) of
        true ->
          ok;
        _ ->
          put(nts, [{Symbol,Index}|L])
      end
  end.

verify_rules() ->
  LHS = erase(lhs),
  NTs = erase(nts),
  [Root|NonRoots] = lists:reverse(LHS),
  lists:foreach(fun({Sym,Idx}) ->
                    case proplists:is_defined(Sym, NTs) of
                      true ->
                        ok;
                      _ ->
                        io:format("neotoma warning: rule '~s' is unused. ~p~n", [Sym,Idx])
                    end
                end, NonRoots),
  lists:foreach(fun({S,I}) ->
                    case proplists:is_defined(S, LHS) of
                      true ->
                        ok;
                      _ ->
                        io:format("neotoma error: nonterminal '~s' has no reduction. (found at ~p) No parser will be generated!~n", [S,I]),
                        exit({neotoma, {no_reduction, list_to_atom(S)}})
                    end
                end, NTs),
    Root.
