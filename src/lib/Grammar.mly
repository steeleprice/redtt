%{
  open TmUtil
  open RedBasis
  open Bwd
  open BwdNotation
  module E = ESig
  module R = ResEnv
%}

%token <int> NUMERAL
%token <string> ATOM
%token <string option> HOLE_NAME
%token LSQ RSQ LPR RPR LGL RGL
%token COLON COLON_ANGLE COMMA DOT
%token EQUALS
%token RIGHT_ARROW RRIGHT_ARROW
%token AST TIMES HASH AT BACKTICK IN
%token BOOL UNIV LAM CONS CAR CDR TT FF IF HCOM COM COE LET DEBUG CALL
%token THEN ELSE
%token IMPORT
%token TYPE PRE KAN
%token EOF


%start <ESig.esig> esig
%%

edecl:
  | LET; a = ATOM; sch = escheme; EQUALS; tm = eterm
    { E.Define (a, sch, tm) }
  | DEBUG; f = debug_filter
    { E.Debug f }
  | IMPORT; a = ATOM
    { E.Import a }

debug_filter:
  | { `All }
  | a = ATOM
    { match a with
      | "all" -> `All
      | "constraints" -> `Constraints
      | _ -> failwith "Invalid debug filter: try 'all' or 'constraints' " }

atomic_eterm:
  | BACKTICK; t = tm
    { E.Quo t }
  | a = HOLE_NAME;
    { E.Hole a }
  | TYPE
    { E.Type }
  | LGL; es = separated_list(COMMA, eterm); RGL
    { E.Tuple es }
  | LPR; e = eterm; RPR
    { e }
  | a = ATOM;
    { if a = "_" then E.Hope else E.Var a }
  | n = NUMERAL;
    { E.Num n }
  | BOOL
    { E.Bool }
  | TT
    { E.Tt }
  | FF
    { E.Ff }


eframe:
  | e = atomic_eterm
    { E.App e }
  | DOT CAR
    { E.Car }
  | DOT CDR
    { E.Cdr }

eterm:
  | e = atomic_eterm
    { e }
  | e = atomic_eterm; fs = nonempty_list(eframe)
    { E.Cut (e, fs) }
  | LAM; xs = list(ATOM); RIGHT_ARROW; e = eterm
    { E.Lam (xs, e)   }
  | LET; name = ATOM; COLON; ty = eterm; EQUALS; tm = eterm; IN; body = eterm
    { E.Let {name; ty = Some ty; tm; body} }
  | LET; name = ATOM; EQUALS; tm = eterm; IN; body = eterm
    { E.Let {name; ty = None; tm; body} }

  | IF; e0 = eterm; THEN; e1 = eterm; ELSE; e2 = eterm
    { E.If (e0, e1, e2) }

  | tele = nonempty_list(epi_cell); RIGHT_ARROW; cod = eterm
    { E.Pi (tele, cod) }

  | tele = nonempty_list(epi_cell); TIMES; cod = eterm
    { E.Sg (tele, cod) }

  | dom = atomic_eterm; RIGHT_ARROW; cod = eterm
    { E.Pi (["_", dom], cod) }

  | dom = atomic_eterm; TIMES; cod = eterm
    { E.Sg (["_", dom], cod) }


escheme:
  | tele = list(escheme_cell); COLON; cod = eterm
    { (tele, cod) }

escheme_cell:
  | LPR; a = ATOM; COLON; ty = eterm; RPR
    { (a, ty) }

epi_cell:
  | LPR; a = ATOM; COLON; ty = eterm; RPR
    { (a, ty) }

esig:
  | d = edecl; esig = esig
    { d :: esig }
  | EOF
    { [] }










tele_with_env:
  | dom = tm; rest = tele_with_env
    { fun env ->
      let env' = R.bind "_" env in
      let tele, env'' = rest env' in
      TCons (None, dom env, tele), env'' }

  | LSQ; x = ATOM; COLON; dom = tm; RSQ; rest = tele_with_env
    { fun env ->
      let env' = R.bind x env in
      let tele, env'' = rest env' in
      TCons (Some x, dom env, tele), env'' }

  | cod = tm
    { fun env ->
      TEnd (cod env), env }

tele:
  | tl = tele_with_env
    { fun env ->
      fst @@ tl env}

face(X):
  | LSQ; r0 = tm; EQUALS; r1 = tm; e = X; RSQ
    { fun env ->
      r0 env, r1 env, Some (e env) }

bind(X):
  | LSQ; x = ATOM; RSQ; e = X
    { fun env ->
      Tm.B (Some x, e @@ R.bind x env) }

dimbind(X):
  | LGL; x = ATOM; RGL; e = X
    { fun env ->
      Tm.B (Some x, e @@ R.bind x env) }

multibind(X):
  | e = X
    { fun env ->
      MBEnd (e env) }

  | LSQ; x = ATOM; RSQ; mb = multibind(X)
    { fun env ->
      MBConsVar (Some x, mb @@ R.bind x env) }

  | LGL; xs = list(ATOM); RGL; mb = multibind(X)
    { fun env ->
      MBConsDims (List.map (fun x -> Some x) xs, mb @@ R.bindn xs env) }


elist(X):
  | xs = list(X)
    { fun env ->
      List.map (fun x -> x env) xs}

constrained:
  | ty = tm; sys = elist(face(tm))
    { fun env ->
      ty env, sys env }

kind:
  | KAN
    { Kind.Kan }
  | PRE
    { Kind.Pre }
  | { Kind.Kan }

tm:
  | BOOL
    { fun _env ->
      make_node $startpos $endpos @@ Tm.Bool }

  | TT
    { fun _env ->
      make_node $startpos $endpos @@ Tm.Tt }

  | FF
    { fun _env ->
      make_node $startpos $endpos @@ Tm.Ff }

  | i = NUMERAL
    { fun _env ->
      make_dim_const $startpos $endpos i }

  | LPR; UNIV; k = kind; i = NUMERAL; RPR
    { fun _env ->
      make_node $startpos $endpos @@
      Tm.Univ {kind = k; lvl = Lvl.Const i} }

  | LPR; RIGHT_ARROW; tele = tele; RPR
    { fun env ->
      pi_from_tele (Some ($startpos, $endpos)) @@ tele env }

  | LPR; AST; tele = tele; RPR
    { fun env ->
      sg_from_tele (Some ($startpos, $endpos)) @@ tele env }

  | LPR; TIMES; tele = tele; RPR
    { fun env ->
      sg_from_tele (Some ($startpos, $endpos)) @@ tele env }

  | LPR; HASH; mb = multibind(constrained); RPR
    { fun env ->
      ext_from_multibind $startpos $endpos @@ mb env }

  | LPR; rst = constrained; RPR
    { fun env ->
      let ty, sys = rst env in
      make_node $startpos $endpos @@
      Tm.Rst {ty; sys}}

  | LPR; LAM; mb = multibind(tm); RPR
    { fun env ->
      lam_from_multibind (Some ($startpos, $endpos)) @@ mb env }

  | LPR; CONS; e0 = tm; e1 = tm; RPR
    { fun env ->
      make_node $startpos $endpos @@
      Tm.Cons (e0 env, e1 env) }

  | e = cmd
    { fun env ->
      make_node $startpos $endpos @@
      Tm.Up (e env) }

  | LPR; LET; LSQ; x = ATOM; e0 = cmd; RSQ; e1 = tm; RPR
    { fun env ->
      make_node $startpos $endpos @@
      Tm.Let (e0 env, Tm.B (Some x, e1 @@ R.bind x env))}

head:
  | a = ATOM
    { fun env ->
      match R.get a env with
      | `Ix i -> Tm.Ix (i, `Only)
      | `Ref r -> Tm.Ref (r, `Only) }

  | LPR; HCOM; r0 = tm; r1 = tm; ty = tm; cap = tm; sys = elist(face(dimbind(tm))); RPR
    { fun env ->
      Tm.HCom {r = r0 env; r' = r1 env; ty = ty env; cap = cap env; sys = sys env} }

  | LPR; COM; r0 = tm; r1 = tm; ty = dimbind(tm); cap = tm; sys = elist(face(dimbind(tm))); RPR
    { fun env ->
      Tm.Com {r = r0 env; r' = r1 env; ty = ty env; cap = cap env; sys = sys env} }

  | LPR; COE; r0 = tm; r1 = tm; ty = dimbind(tm); tm = tm; RPR
    { fun env ->
      Tm.Coe {r = r0 env; r' = r1 env; ty = ty env; tm = tm env} }

  | LPR; COLON_ANGLE; ty = tm; tm = tm; RPR
    { fun env ->
      Tm.Down {ty = ty env; tm = tm env} }

cmd:
  | c = cut
    { fun env ->
      c env }

cut:
  | hd = head
    { fun env ->
      hd env, Emp }

  | LPR; CAR; e = cut; RPR
    { fun env ->
      let hd, fs = e env in
      hd, fs #< Tm.Car }

  | LPR; CDR; e = cut; RPR
    { fun env ->
      let hd, fs = e env in
      hd, fs #< Tm.Cdr }

  | LPR; CALL; e = cut; RPR
    { fun env ->
      let hd, fs = e env in
      hd, fs #< Tm.LblCall }

  | LPR; e = cut; arg0 = tm; rest = elist(tm); RPR
    { fun env ->
      let hd, fs = e env in
      let args = arg0 env :: rest env in
      hd, (fs <>< List.map (fun t -> Tm.FunApp t) args) }

  | LPR; AT; e = cut; args = elist(tm); RPR
    { fun env ->
      let hd, fs = e env in
      hd, fs #< (Tm.ExtApp (args env)) }

  | LPR; IF; mot = bind(tm); scrut = cut; tcase = tm; fcase = tm; RPR
    { fun env ->
      let hd, fs = scrut env in
      hd, fs #< (Tm.If {mot = mot env; tcase = tcase env; fcase = fcase env}) }
