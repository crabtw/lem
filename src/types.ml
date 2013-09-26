(**************************************************************************)
(*                        Lem                                             *)
(*                                                                        *)
(*          Dominic Mulligan, University of Cambridge                     *)
(*          Francesco Zappa Nardelli, INRIA Paris-Rocquencourt            *)
(*          Gabriel Kerneis, University of Cambridge                      *)
(*          Kathy Gray, University of Cambridge                           *)
(*          Peter Boehm, University of Cambridge (while working on Lem)   *)
(*          Peter Sewell, University of Cambridge                         *)
(*          Scott Owens, University of Kent                               *)
(*          Thomas Tuerk, University of Cambridge                         *)
(*                                                                        *)
(*  The Lem sources are copyright 2010-2013                               *)
(*  by the UK authors above and Institut National de Recherche en         *)
(*  Informatique et en Automatique (INRIA).                               *)
(*                                                                        *)
(*  All files except ocaml-lib/pmap.{ml,mli} and ocaml-libpset.{ml,mli}   *)
(*  are distributed under the license below.  The former are distributed  *)
(*  under the LGPLv2, as in the LICENSE file.                             *)
(*                                                                        *)
(*                                                                        *)
(*  Redistribution and use in source and binary forms, with or without    *)
(*  modification, are permitted provided that the following conditions    *)
(*  are met:                                                              *)
(*  1. Redistributions of source code must retain the above copyright     *)
(*  notice, this list of conditions and the following disclaimer.         *)
(*  2. Redistributions in binary form must reproduce the above copyright  *)
(*  notice, this list of conditions and the following disclaimer in the   *)
(*  documentation and/or other materials provided with the distribution.  *)
(*  3. The names of the authors may not be used to endorse or promote     *)
(*  products derived from this software without specific prior written    *)
(*  permission.                                                           *)
(*                                                                        *)
(*  THIS SOFTWARE IS PROVIDED BY THE AUTHORS ``AS IS'' AND ANY EXPRESS    *)
(*  OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED     *)
(*  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE    *)
(*  ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY       *)
(*  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL    *)
(*  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE     *)
(*  GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS         *)
(*  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER  *)
(*  IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR       *)
(*  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN   *)
(*  IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.                         *)
(**************************************************************************)

open Reporting_basic

type tnvar = 
  | Ty of Tyvar.t
  | Nv of Nvar.t

let pp_tnvar ppf tnv =
  match tnv with
  | Ty(v) -> Tyvar.pp ppf v
  | Nv(v) -> Nvar.pp ppf v

let tnvar_to_rope tnv =
  match tnv with
  | Ty(v) -> Tyvar.to_rope v
  | Nv(v) -> Nvar.to_rope v

let tnvar_compare tn1 tn2 = match (tn1,tn2) with
  | (Ty v1,Ty v2) -> Tyvar.compare v1 v2
  | (Ty _ , _) -> 1
  | (_ , Ty _) -> -1
  | (Nv v1, Nv v2) -> Nvar.compare v1 v2

let tnvar_to_name = function
     Ty v -> Name.from_rope (Tyvar.to_rope v)
   | Nv v -> Name.from_rope (Nvar.to_rope v)

module TNvar = struct
  type t = tnvar
  let compare tn1 tn2 = tnvar_compare tn1 tn2
  let pp ppf tnv = pp_tnvar ppf tnv
end

module TNfmap = Finite_map.Fmap_map(TNvar)
module TNset' = Set.Make(TNvar)
module TNset = struct
  include TNset'
  let pp ppf tvset =
    Format.fprintf ppf "{@[%a@]}"
      (Pp.lst ",@ " TNvar.pp)
      (TNset'.elements tvset)
end

module Pfmap = Finite_map.Fmap_map(Path)

type t = { mutable t : t_aux }
and t_aux =
  | Tvar of Tyvar.t
  | Tfn of t * t
  | Ttup of t list
  | Tapp of t list * Path.t
  | Tne of nexp
  | Tuvar of t_uvar
and t_uvar = { index : int; mutable subst : t option }

and nexp = { mutable nexp : nexp_aux }
and nexp_aux = 
  | Nvar of Nvar.t
  | Nconst of int
  | Nadd of nexp * nexp
  | Nmult of nexp *nexp
  | Nneg of nexp
  | Nuvar of n_uvar
and n_uvar = { nindex : int; mutable nsubst : nexp option }

type range =
  | LtEq of Ast.l * nexp
  | Eq of Ast.l * nexp
  | GtEq of Ast.l * nexp

let free_vars t =
  let rec f t acc =
    match t.t with
      | Tvar(tv) -> TNset.add (Ty tv) acc
      | Tfn(t1,t2) -> f t2 (f t1 acc)
      | Ttup(ts) -> 
          List.fold_left (fun acc t -> f t acc) acc ts
      | Tapp(ts,_) ->
          List.fold_left (fun acc t -> f t acc) acc ts
      | Tne n -> f_n n acc
      | Tuvar _ -> assert false (*TVset.empty*)
   and f_n n acc = 
    match n.nexp with
      | Nvar(nv) -> TNset.add (Nv nv) acc
      | Nconst _ -> acc
      | Nadd(n1,n2) | Nmult(n1,n2) -> f_n n1 (f_n n2 acc)
      | Nneg(n) -> f_n n acc
      | Nuvar _ -> assert false
  in
    f t TNset.empty

let rec tnvar_to_tyvar_lst tnlst =
  match tnlst with 
    | [] -> []
    | Ty(tv)::tnlst -> tv::(tnvar_to_tyvar_lst tnlst)
    | Nv _ ::tnlst -> (tnvar_to_tyvar_lst tnlst)

let rec tnvar_to_nvar_lst tnlst =
  match tnlst with 
    | [] -> []
    | Ty _ ::tnlst -> (tnvar_to_nvar_lst tnlst)
    | Nv(n)::tnlst -> n::(tnvar_to_nvar_lst tnlst)

let rec tnvarp_to_tvarp_lst tplst =
   match tplst with
     | [] -> []
     | (p,Ty(tv))::tplst -> (p,tv)::(tnvarp_to_tvarp_lst tplst)
     | (_ , Nv _ )::tplst -> (tnvarp_to_tvarp_lst tplst)

let rec compare_nexp n1 n2 =
  if n1 = n2 then
    0
  else
    match (n1.nexp,n2.nexp) with
     | (Nvar(v1), Nvar(v2)) -> Nvar.compare v1 v2
     | (Nvar _ , _) -> 1
     | (_ , Nvar _) -> -1
     | (Nconst(c1),Nconst(c2)) -> 
       if c1 = c2 then 0
       else if c1 > c2 then 1 else -1
     | (Nconst _, _) -> 1
     | (_, Nconst _) -> -1
     | (Nadd(n1,n2),Nadd(n1',n2')) | (Nmult(n1,n2),Nmult(n1',n2')) ->
        let c = compare_nexp n1 n1' in
        if c = 0 then compare_nexp n2 n2'
        else c
     | (Nadd _, _) -> 1
     | (_,Nadd _) -> -1
     | (Nmult _ , _) -> 1
     | (_ , Nmult _) -> -1
     | (Nneg(n1),Nneg(n2)) -> compare_nexp n2 n1
     | (Nneg _, _) -> 1
     | (_,Nneg _) -> -1
     | (Nuvar(u1), Nuvar(u2)) -> 
        if u1 == u2 then
          0
        else
          match (u1.nsubst, u2.nsubst) with
            | (Some(n1), Some(n2)) ->
                compare_nexp n1 n2
            | (Some _, None) -> 1
            | (None, Some _) -> -1
            | (None, None) -> (*0*) compare u1.nindex u2.nindex

let rec compare t1 t2 =
  if t1 == t2 then
    0
  else
    match (t1.t,t2.t) with
    | (Tvar(tv1), Tvar (tv2)) ->
        Tyvar.compare tv1 tv2
    | (Tvar _, _) -> 1
    | (_, Tvar _) -> -1
    | (Tfn(t1,t2), Tfn(t3,t4)) ->
        let c = compare t1 t3 in
          if c = 0 then
            compare t2 t4
          else
            c
    | (Tfn _, _) -> 1
    | (_, Tfn _) -> -1
    | (Ttup(ts1), Ttup(ts2)) ->
        Util.compare_list compare ts1 ts2
    | (Ttup _, _) -> 1
    | (_, Ttup _) -> -1
    | (Tapp(ts1,p1), Tapp(ts2,p2)) -> 
        let c = Util.compare_list compare ts1 ts2 in
          if c = 0 then
            Path.compare p1 p2
          else
            c
    | (Tapp _, _) -> 1
    | (_, Tapp _) -> -1
    | (Tne(n1),Tne(n2)) -> compare_nexp n1 n2
    | (Tne _, _) -> 1
    | (_, Tne _) -> -1
    | (Tuvar(u1), Tuvar(u2)) -> 
        if u1 == u2 then
          0
        else
          match (u1.subst, u2.subst) with
            | (Some(t1), Some(t2)) ->
                compare t1 t2
            | (Some _, None) -> 1
            | (None, Some _) -> -1
            | (None, None) -> 0

module PT = struct
  type u = t
  type t = Path.t * u
  let compare (p1,t1) (p2,t2) =
    let c = Path.compare p1 p2 in
      if c = 0 then
        compare t1 t2
      else
        c
end

module PTset = Set.Make(PT)

let multi_fun (ts : t list) (t : t) : t =
  List.fold_right (fun t1 t2 -> { t = Tfn(t1,t2); }) ts t

let tnvar_to_type tnv =
 match tnv with
 | Ty(v) -> { t = Tvar(v) }
 | Nv(v) -> { t = Tne( { nexp = Nvar(v) } ) }

let rec tnvar_split tnvs = 
  match tnvs with
  | [] -> [],[]
  | (Ty v)::tnvs -> let (nvars,tvars) = tnvar_split tnvs in
     (nvars,(Ty v)::tvars)
  | (Nv v)::tnvs -> let (nvars,tvars) = tnvar_split tnvs in
     ((Nv v)::nvars,tvars)

let rec type_subst_aux (substs : t TNfmap.t) (t : t) = 
  match t.t with
    | Tvar(s) ->
        (match TNfmap.apply substs (Ty s) with
           | Some(t) -> Some(t)
           | None -> None)
    | Tfn(t1,t2) -> 
        begin
          match (type_subst_aux substs t1, type_subst_aux substs t2) with
            | (None,None) -> None
            | (Some(t),None) -> Some({ t = Tfn(t, t2) })
            | (None,Some(t)) -> Some({ t = Tfn(t1, t) })
            | (Some(t1),Some(t2)) -> Some({ t = Tfn(t1, t2) })
        end
    | Ttup(ts) -> 
        begin
          match Util.map_changed (type_subst_aux substs) ts with
            | None -> None
            | Some(ts) -> Some({ t = Ttup(ts) })
        end
    | Tapp(ts,p) -> 
        begin
          match Util.map_changed (type_subst_aux substs) ts with
            | None -> None
            | Some(ts) -> Some({ t = Tapp(ts,p) })
        end
    | Tne(n) -> 
        begin
          match (nexp_subst_aux substs n) with
            | n,false -> None
            | n,true -> Some({t = Tne(n)})
        end
    | Tuvar _ -> 
        assert false

and nexp_subst_aux_help (substs : t TNfmap.t) (n: nexp) =
  match n.nexp with
    | Nvar(s) ->
        (match TNfmap.apply substs (Nv s) with
           | Some({t = Tne(n)}) -> Some(n)
           | _ -> assert false)
    | Nconst _ -> None
    | Nadd(n1,n2) -> 
        begin
          match (nexp_subst_aux_help substs n1, nexp_subst_aux_help substs n2) with
            | (None,None) -> None
            | (Some(n),None) -> Some({ nexp = Nadd(n, n2) })
            | (None,Some(n)) -> Some({ nexp = Nadd(n1, n) })
            | (Some(n1),Some(n2)) -> Some({ nexp = Nadd(n1, n2) })
        end
    | Nmult(n1,n2) -> 
        begin
          match (nexp_subst_aux_help substs n1, nexp_subst_aux_help substs n2) with
            | (None,None) -> None
            | (Some(n),None) -> Some({ nexp = Nmult(n, n2) })
            | (None,Some(n)) -> Some({ nexp = Nmult(n1, n) })
            | (Some(n1),Some(n2)) -> Some({ nexp = Nmult(n1, n2) })
        end
    | Nneg(n) ->
        begin
        match nexp_subst_aux_help substs n with
         | None -> None
         | Some(n) -> Some({nexp = Nneg(n)})
        end
    | Nuvar _ -> assert false

and nexp_subst_aux (substs : t TNfmap.t) (n : nexp) : nexp * bool = 
  if TNfmap.is_empty substs then
    n, false
  else
    match nexp_subst_aux_help substs n with
      | None -> n,false
      | Some(n) -> n,true

let nexp_subst (substs : t TNfmap.t) (n : nexp) : nexp =
   let n,_ = nexp_subst_aux substs n in
   n

let type_subst (substs : t TNfmap.t) (t : t) : t = 
  if TNfmap.is_empty substs then
    t
  else
    match type_subst_aux substs t with
      | None -> t
      | Some(t) -> t

let rec resolve_subst (t : t) : t = match t.t with
  | Tuvar({ subst=Some(t') } as u) ->
      let t'' = resolve_subst t' in
        (match t''.t with
           | Tuvar(_) ->
               u.subst <- Some(t'');
               t''
           | x -> 
               t.t <- x;
               t)
  | _ ->
      t

let rec resolve_nexp_subst (n : nexp) : nexp = match n.nexp with
  | Nuvar({ nsubst = Some(n')} as u) ->
     let n'' = resolve_nexp_subst n' in
      (match n''.nexp with
        | Nuvar(_) -> 
          u.nsubst <- Some(n'');
          n''
        | x -> n.nexp <- x; n)
   | _ -> n

type const_descr_ref = int

let string_of_const_descr_ref = string_of_int

let nil_const_descr_ref = 0
let is_nil_const_descr_ref r = (r = 0)

module Cdmap = Finite_map.Fmap_map(
struct 
  type t = const_descr_ref
  let compare = Pervasives.compare
end)

module Cdset = Set.Make(
struct 
  type t = const_descr_ref
  let compare = Pervasives.compare
end)

type 'a cdmap = const_descr_ref * 'a Cdmap.t

let cdmap_lookup (c_env_count, c_env_map) c = Cdmap.apply c_env_map c

let cdmap_update (c_env_count, c_env_map) c_id c_d =
    (c_env_count, Cdmap.insert c_env_map (c_id, c_d))

let cdmap_insert (c_env_count, c_env_map) c_d = 
  ((c_env_count+1, Cdmap.insert c_env_map (c_env_count, c_d)), c_env_count)

let cdmap_empty () = (nil_const_descr_ref + 1, Cdmap.empty)



type constr_family_descr = { 
   constr_list : const_descr_ref list; 
   (** a list of all the constructors *)

   constr_exhaustive : bool;
   (** is this family of constructors exhaustive, or does a special catch-other case needs adding? *)

   constr_case_fun : const_descr_ref option 
   (** the case split function for this constructor list, [None] means that pattern matching is used. *)
}

type type_target_rep =
  | TR_rename of Ast.l * bool * Name.t
  | TR_new_ident of Ast.l * bool * Ident.t

type type_descr = { 
  type_tparams : tnvar list;
  type_abbrev : t option;
  type_varname_regexp : string option;
  type_fields : (const_descr_ref list) option;
  type_constr : constr_family_descr list;
  type_target_rep : type_target_rep Target.Targetmap.t
}


type class_descr = { 
  class_tparam : tnvar;
  class_record : Path.t; 
  class_methods : (const_descr_ref * const_descr_ref) list;
  class_target_rep : type_target_rep Target.Targetmap.t
}

type tc_def = 
  | Tc_type of type_descr 
  | Tc_class of class_descr

let mk_tc_type_abbrev vars abbrev = Tc_type { 
  type_tparams = vars;
  type_abbrev = Some abbrev;
  type_varname_regexp = None;
  type_fields = None;
  type_constr = [];
  type_target_rep = Target.Targetmap.empty
}

let mk_tc_type vars reg = Tc_type { 
  type_tparams = vars;
  type_abbrev = None;
  type_varname_regexp = reg;
  type_fields = None;
  type_constr = [];
  type_target_rep = Target.Targetmap.empty
}

type type_defs = tc_def Pfmap.t

let env_no_type_exp l p = 
  let _ = Format.flush_str_formatter() in
  let _ = Format.fprintf Format.str_formatter "environment does not contain type '%a'!" Path.pp p in
  let m = Format.flush_str_formatter() in
  Reporting_basic.Fatal_error (Reporting_basic.Err_internal(l, m))

let env_no_update_exp l p = 
  let _ = Format.flush_str_formatter() in
  let _ = Format.fprintf Format.str_formatter "update of type-description not possible for type '%a'!" Path.pp p in
  let m = Format.flush_str_formatter() in
  Reporting_basic.Fatal_error (Reporting_basic.Err_internal(l, m))

let type_defs_update_tc_type (l : Ast.l) (d : type_defs) (p : Path.t) (up : type_descr -> type_descr option) : type_defs =
begin
  let td = match (Pfmap.apply d p) with
    | Some (Tc_type td) -> td
    | _ -> raise (env_no_type_exp (Ast.Trans (false, "type_defs_update_tc_type", Some l)) p)
  in
  match up td with
    | Some td' -> Pfmap.insert d (p, Tc_type td')
    | None -> raise (env_no_update_exp l p)
end

let type_defs_update_fields l (d : type_defs) (p : Path.t) (fl : const_descr_ref list) : type_defs =
  let l = Ast.Trans (false, "type_defs_update_fields", Some l) in
  type_defs_update_tc_type l d p (fun tc -> Some {tc with type_fields = Some fl})

let type_defs_add_constr_family l (d : type_defs) (p : Path.t) (cf : constr_family_descr) : type_defs =
  let l = Ast.Trans (false, "type_defs_add_constr_family", Some l) in
  type_defs_update_tc_type l d p (fun tc -> Some {tc with type_constr = cf :: tc.type_constr})

let type_defs_lookup l (d : type_defs) (p : Path.t) =
    let l = Ast.Trans (false, "type_defs_lookup", Some l) in
    match (Pfmap.apply d p) with
      | Some (Tc_type td) -> td
      | _ -> raise (env_no_type_exp l p)

let type_defs_update (d : type_defs) (p : Path.t) td =
    Pfmap.insert d (p, Tc_type td)

let type_defs_lookup_typ l (d : type_defs) (t : t) =
    match t with 
      | { t = Tapp(_, p) } -> Some (type_defs_lookup l d p)
      | _ -> None

let type_defs_get_constr_families l (d : type_defs) (t : t) (c : const_descr_ref) : constr_family_descr list =
  match type_defs_lookup_typ l d t with 
    | None -> []
    | Some td -> List.filter (fun fs -> List.mem c fs.constr_list) td.type_constr

type instance = {
  inst_l : Ast.l;
  inst_binding : Path.t; 
  inst_class : Path.t;
  inst_type : t;
  inst_tyvars : tnvar list;
  inst_constraints : (Path.t * tnvar) list;
  inst_methods : (const_descr_ref * const_descr_ref) list;
  inst_dict : const_descr_ref
}

module IM = Map.Make(struct type t = int let compare = Pervasives.compare end)
open Format
open Pp

let rec pp_type ppf t =
  pp_open_box ppf 0;
  (match t.t with
     | Tvar(tv) ->
         Tyvar.pp ppf tv
     | Tfn(t1,t2) ->
         fprintf ppf "(@[%a@])@ ->@ %a"
           pp_type t1
           pp_type t2
     | Ttup(ts) ->
         fprintf ppf "(@[%a@])"
           (lst "@ *@ " pp_type) ts
     | Tapp([],p) ->
         Path.pp ppf p
     | Tapp([t],p) ->
         fprintf ppf "%a@ %a"
           Path.pp p
           pp_type t
     | Tapp(ts,p) ->
         fprintf ppf "%a @[%a@]"
           Path.pp p
           (lst "@ " pp_type) ts
     | Tne(n) -> fprintf ppf "%a" 
                   pp_nexp n
     | Tuvar(u) ->
         fprintf ppf "_");
         
         (*fprintf ppf "<@[%d,@ %a@]>" 
           u.index
           (opt pp_type) u.subst);*)
          
  pp_close_box ppf ()
and
 pp_nexp ppf n =
  pp_open_box ppf 0;
  (match n.nexp with
     | Nuvar nu -> fprintf ppf "_" (*   fprintf ppf "_ (%d)" nu.nindex *)
     | Nvar(nv) ->
         Nvar.pp ppf nv
     | Nconst(i) ->
         fprintf ppf "%d" i
     | Nadd(i,j) ->
         fprintf ppf "(%a + %a)"
             pp_nexp i
             pp_nexp j
     | Nmult(i,j) ->
         fprintf ppf "(%a * %a)" 
            pp_nexp i
            pp_nexp j
     | Nneg(n) -> fprintf ppf "- %a"
            pp_nexp n);
  pp_close_box ppf ()

let pp_range ppf = function
  | GtEq(_,n) -> fprintf ppf "%a >= 0" pp_nexp n
  | Eq(_,n)   -> fprintf ppf "%a = 0" pp_nexp n
  | LtEq(_,n) -> fprintf ppf "%a <= 0" pp_nexp n

let pp_tc ppf = function
  | Tc_type(d) ->
      begin
        match d.type_abbrev with
          | None -> fprintf ppf "%s" (string_of_int (List.length d.type_tparams))
          | Some(t) -> fprintf ppf "%a" pp_type t
      end
  | Tc_class _ ->
      (*TODO*)
      ()

let pp_tdefs ppf tds =
  Pfmap.pp_map Path.pp pp_tc ppf tds

let pp_class_constraint ppf (p, tv) =
  fprintf ppf "(@[%a@ %a@])"
    Path.pp p
    pp_tnvar tv

let pp_instance_constraint ppf (p, t) =
  fprintf ppf "(@[%a@ %a@])"
    Path.pp p
    pp_type t

let pp_instance ppf inst =
  fprintf ppf "@[<2>forall@ (@[%a@]).@ @[%a@]@ =>@ %a@]@ (%a)"
    (lst ",@," pp_tnvar) inst.inst_tyvars
    (lst "@ " pp_class_constraint) inst.inst_constraints
    pp_type inst.inst_type 
    Path.pp inst.inst_binding

let pp_instance_defs ppf ipf =
  Pfmap.pp_map Path.pp (lst ",@," pp_instance) ppf ipf

let t_to_string t =
  pp_to_string (fun ppf -> pp_type ppf t)

let t_to_var_name t =
  let aux t = match t.t with
     | Tvar(tv) -> "x"
     | Tfn(t1,t2) -> "f"
     | Ttup(ts) -> "p"
     | Tapp(ts,p) -> Name.to_string (Path.get_name p)
     | Tne(n) -> "x"
     | Tuvar(u) -> "x"
  in 
  let n_s = String.sub (aux t) 0 1 in
  let n_s' = let c = Char.code (String.get n_s 0) in 
             if 96 < c && c < 123 then n_s else "x" in
  Name.from_rope (Ulib.Text.of_string n_s')

let nexp_to_string n =
  pp_to_string (fun ppf -> pp_nexp ppf n)

let range_to_string r =
  pp_to_string (fun ppf -> pp_range ppf r)

let rec head_norm (d : type_defs) (t : t) : t = 
  let t = resolve_subst t in
    match t.t with
      | Tapp(ts,p) ->
          (match Pfmap.apply d p with
             | None ->
                 (*
                 Path.pp Format.std_formatter p;
                 Format.fprintf Format.std_formatter "@\n";
                 pp_tdefs Format.std_formatter d;
                 Format.fprintf Format.std_formatter "@\n";
                  *)
                 raise (Reporting_basic.Fatal_error (Reporting_basic.Err_internal(Ast.Unknown, "head_norm: env did not contain type!")))
             | Some(Tc_type(dc)) -> Util.option_default_map dc.type_abbrev t (fun t -> head_norm d (type_subst (TNfmap.from_list2 dc.type_tparams ts) t))
             | Some(Tc_class _) ->
                 raise (Reporting_basic.err_unreachable true Ast.Unknown "head_norm: called on a type-class!"))
      | _ -> 
          t

let dest_fn_type (d_opt : type_defs option) (t : t) : (t * t) option =
  let t' = match d_opt with None -> t | Some d -> head_norm d t in
  match t'.t with
    | Tfn(t1, t2) -> Some (t1, t2)
    | _ -> None

let rec strip_fn_type d_opt t =
  match dest_fn_type d_opt t with
    | None -> ([], t)
    | Some (t1, t2) -> begin
        let (al, bt) = strip_fn_type d_opt t2 in
        (t1 :: al, bt)
      end
                       

let t_to_tnv t =
  match t.t with
    | Tvar(tv) -> Ty tv
    | Tne({ nexp = Nvar(nv)}) -> Nv nv
    | _ -> assert false

let nexps_match n_pat n =
 (* TODO think about when and where to normalize *)
 match (n_pat.nexp,n.nexp) with
  | (Nvar(n),_) -> true
  | (Nconst(n),Nconst(n')) -> n=n'
  | _ -> false

let types_match t_pat t =
  match (t_pat.t,t.t) with
    | (Tvar(tv), _) -> true
    | (Tfn(tv1,tv2), Tfn(t1,t2)) -> true
    | (Ttup(tvs), Ttup(ts)) ->
        List.length tvs = List.length ts
    | (Tapp(tvs,p), Tapp(ts,p')) ->
        Path.compare p p' = 0
    | (Tne(n),Tne(n')) -> nexps_match n n'
    | (Tuvar _, _) -> assert false
    | _ -> false

let do_nexp_match n_pat n =
  (* TODO think about when and where to normalize *)
  match (n_pat.nexp,n.nexp) with
    | (Nvar(n'),_) -> TNfmap.from_list [(Nv n'),{t = Tne(n)}]
    | (Nconst(n),_) -> TNfmap.empty
    | _ -> assert false

let do_type_match t_pat t =
  match (t_pat.t,t.t) with
    | (Tvar(tv), _) -> TNfmap.from_list [(Ty tv),t]
    | (Tfn(tv1,tv2), Tfn(t1,t2)) ->
        TNfmap.from_list [(t_to_tnv tv1,t1); (t_to_tnv tv2,t2)]
    | (Ttup(tvs), Ttup(ts)) ->
        TNfmap.from_list2 (List.map t_to_tnv tvs) ts
    | (Tapp(tvs,p), Tapp(ts,p')) ->
        TNfmap.from_list2 (List.map t_to_tnv tvs) ts
    | (Tne(n),Tne(n')) -> do_nexp_match n n'
    | _ -> assert false


type i_env = (instance list) Pfmap.t 
let empty_i_env = Pfmap.empty

let i_env_add (m : i_env) (i : instance)  : i_env =
  let other_insts =  match Pfmap.apply m i.inst_class with
    | None -> []
    | Some(l) -> l
  in
  Pfmap.insert m (i.inst_class,i::other_insts)

let rec get_matching_instance d (p,t) (instances : (instance list) Pfmap.t) : (instance * t TNfmap.t) option = 
  let t = head_norm d t in 
    match Pfmap.apply instances p with
      | None -> None
      | Some(possibilities) ->
          try
            let i = List.find (fun i -> types_match i.inst_type t) possibilities in
            let subst = do_type_match i.inst_type t in
              Some(i, subst)
          with
              Not_found -> None

let type_mismatch l m t1 t2 = 
  let t1 = t_to_string t1 in
  let t2 = t_to_string t2 in
    raise (err_type l ("type mismatch: " ^ m ^ "\n" ^ t1 ^ "\nand\n" ^ t2))

let nexp_mismatch l n1 n2 =
  let n1 = nexp_to_string n1 in
  let n2 = nexp_to_string n2 in
    raise (err_type l ("numeric expression mismatch:\n" ^ n1 ^ "\nand\n" ^ n2))

let inconsistent_constraints r l =
  raise (err_type l ("Constraints, including " ^ range_to_string r ^ " are inconsistent\n"))

(* Converts to linear normal form, summation of (optionally constant-multiplied) variables, with the "smallest" variable on the left *)
let normalize nexp =
 (*Note it is only okay to call make_n if the nexp is certainly NOT an nuvar*)
 let nBang base n = base.nexp <- n; base in
 let make_c i = { nexp = Nconst i } in
 let make_n n = {nexp = n} in
 let make_mul base n i = match i with 
                    | 0 -> make_c 0
                    | 1 -> n
                    | _ -> nBang base (Nmult (n,make_c i)) in 
  let make_ordered base cl cr nl nr i v =
    match (compare_nexp cl cr) with
      | -1 -> nBang base (Nadd(nr,nl))
      | 0 -> make_mul base v i
      | _ -> nBang base (Nadd(nl,nr)) in
 let rec norm nexp = 
(*    let _ = fprintf std_formatter "norm of %a@ \n" pp_nexp nexp in *)
    match nexp.nexp with
    | Nvar _ | Nconst _ | Nuvar _ -> nexp
    | Nneg(n) -> (
       let n' = norm n in
       match n'.nexp with
        | Nconst(i) -> nBang nexp (Nconst(-1 * i))
        | _ -> norm (make_mul nexp n' (-1)))
    | Nmult(n1,n2) -> (
       let n1',n2' = norm n1,norm n2 in
       let n1',n2' = sort n1',sort n2' in 
       match n1'.nexp,n2'.nexp with
        | Nconst i, Nconst j -> nBang nexp (Nconst (i*j))
        | Nconst 1, _ -> n2' | _, Nconst 1 -> n1'
        | Nvar _ , Nconst _ | Nuvar _ , Nconst _  -> nBang nexp (Nmult(n1',n2'))
        | Nconst _ , Nvar _ | Nconst _ , Nuvar _ -> nBang nexp (Nmult(n2',n1'))
        | Nconst i , Nadd(n1,n2) | Nadd(n1,n2), Nconst i ->
          let n1 = norm (make_n (Nmult((make_c i),n1))) in
          let n2 = norm (make_n (Nmult((make_c i),n2))) in
          let n1 = sort n1 in
          let n2 = sort n2 in
          nBang nexp (Nadd(n1,n2))
        | Nconst i , Nmult(n1,n2) | Nmult(n1,n2), Nconst i ->
          (match n1.nexp with
            | Nvar _ | Nuvar _ -> let n2 = norm (make_n (Nmult((make_c i), n2))) in
                                  let n2 = sort n2 in
                                  nBang nexp (Nmult(n1,n2))
            | _ -> assert false)
        | _ -> assert false ) (*TODO KG Needs to be an actualy error, as must mean that a variable is multiplied by a variable, somewhere *)
    | Nadd(n1,n2) -> (
      let n1',n2' = norm n1,norm n2 in
      let n1',n2' = sort n1',sort n2' in 
      match n1'.nexp,n2'.nexp with
        | Nconst i, Nconst j -> nBang nexp (Nconst(i+j))
        | _,_ -> nBang nexp (Nadd(n1',n2')))
  and
    sort nexp = 
(*     let _ = fprintf std_formatter "sort of %a@ \n" pp_nexp nexp in *)
     match nexp.nexp with 
     | Nvar _ | Nconst _ | Nuvar _ | Nmult _ | Nneg _ -> nexp
     | Nadd(n1,n2) ->
       let n1,n2 = sort n1, sort n2 in
        begin match n1.nexp,n2.nexp with
         | Nconst i , Nconst j -> nBang nexp (Nconst (i+j))
         | Nconst 0, n -> n2 | n , Nconst 0 -> n1 
         | Nconst _ , (Nmult _ | Nvar _ | Nuvar _ ) -> nBang nexp (Nadd(n1,n2))
         | (Nmult _ | Nvar _ | Nuvar _ ) , Nconst _ -> nBang nexp (Nadd(n2,n1))
         | Nuvar _ , Nuvar _ | Nuvar _ , Nvar _ | Nvar _ , Nuvar _ | Nvar _ , Nvar _ -> 
           make_ordered nexp n1 n2 n1 n2 2 n1
         | Nvar _, Nmult(v,n) | Nuvar _, Nmult(v,n) ->
           (match v.nexp,n.nexp with 
            | Nvar _,Nconst i | Nuvar _,Nconst i -> 
              make_ordered nexp n1 v n1 n2 (i+1) n1
             | _ -> assert false)
         | Nmult(v,n), Nvar _ | Nmult(v,n), Nuvar _ ->
              (match v.nexp,n.nexp with 
               | Nvar _ ,Nconst i | Nuvar _, Nconst i -> 
                 make_ordered nexp v n2 n1 n2 (i+1) n2
               | _ -> assert false)
         | Nmult(var1,nc1),Nmult(var2,nc2) ->
              (match var1.nexp,nc1.nexp,var2.nexp,nc2.nexp with 
               | _, Nconst i1, _, Nconst i2 ->
                 make_ordered nexp var1 var2 n1 n2 (i1+i2) var1  
               | _ -> assert false)
         | Nadd(n1l,n1r),Nadd(n2l,n2r) ->
               (match compare_nexp n1r n2r with
                 | -1 -> let sorted = sort (make_n (Nadd(n1l,n2))) in
                         (match sorted.nexp with
                          | Nconst 0 -> n1r
                          | _ -> sort (nBang nexp ( Nadd(sorted, n1r))))
                | 0 -> let rightmost = sort (make_n (Nadd(n1r,n2r))) in
                       let sorted = sort (make_n (Nadd(n1l,n2l))) in
                         (match rightmost.nexp,sorted.nexp with
                           | Nconst 0, n -> sorted
                           | n, Nconst 0 -> rightmost
                           | _ -> sort (nBang nexp (Nadd (sorted,rightmost))))
                | _ -> let sorted = sort (make_n (Nadd(n1,n2l))) in
                        (match sorted.nexp with
                         | Nconst 0 -> n2r
                         | _ -> sort (nBang nexp ( Nadd (sorted, n2r)))))         
         | Nadd(n1l,n1r),n -> (*Add on left, potential nuvar on right*)
              let sorted = sort (make_n (Nadd(n1r,n2))) in
              (match sorted.nexp with 
                 | Nadd(nb,ns) -> 
                   let sorted_left = sort (make_n (Nadd (n1l, nb))) in
                   (match sorted_left.nexp with
                     | Nconst 0 -> ns
                     | _ -> nBang nexp (Nadd(sorted_left,ns)))
                 | Nconst 0 -> n1l
                 | _ -> make_n(Nadd(n1l, sorted))
              )         
         | n, Nadd(n1l,n1r)-> (* Add on right, potential nuvar on left*)
              let sorted = sort (make_n (Nadd(n1r,n1))) in
              (match sorted.nexp with 
                 | Nadd(nb,ns) -> 
                   let sorted_left = sort (make_n (Nadd (n1l, nb))) in
                   (match sorted_left.nexp with
                     | Nconst 0 -> ns
                     | _ -> nBang nexp (Nadd(sorted_left,ns)))
                 | Nconst 0 -> n1l
                 | _ -> nBang nexp (Nadd(n1l, sorted))
              )
         | Nneg _ , _ | _ , Nneg _ -> assert false (*Should have been removed in norm*)
       end
  in 
  let normal = norm nexp in
(*  let _  =  fprintf std_formatter "normal unsorted is %a@ \n" pp_nexp normal in *)
  let sorted = sort normal in
(*  let _ = fprintf std_formatter "sorted normal is %a@ \n" pp_nexp sorted in *)
  sorted

(** [check_equal_with_withness d t1 t2] checks whether [t1] and [t2] are
    equal in [d]. It expands types. If they are equal, [None] is returned. Otherwise,
    a pair of types occuring a the same subposition of [t1] and [t2], which are not
    equal are returned. For example ['a list] and [num list] would return the pair [Some ('a, num)]. *)

type check_equal_witness =
  | CEW_equal               (* no witness found, therefore types are equal *)
  | CEW_type of t * t       (* A type mismatch with the witness *)
  | CEW_nexp of nexp * nexp (* A numeric variable mismatch *)

let rec check_equal_with_withness (d : type_defs) (t1 : t) (t2 : t) : check_equal_witness =
  if t1 == t2 then CEW_equal else
    let t1 = head_norm d t1 in
    let t2 = head_norm d t2 in
      match (t1.t,t2.t) with
        | (Tuvar _, _) -> CEW_type (t1, t2)
        | (_, Tuvar _) -> CEW_type (t1, t2)
        | (Tvar(s1), Tvar(s2)) ->
            if Tyvar.compare s1 s2 = 0 then CEW_equal else CEW_type (t1, t2)
        | (Tfn(t1,t2), Tfn(t3,t4)) ->
          begin
            match check_equal_with_withness d t1 t3 with
              | CEW_equal -> check_equal_with_withness d t2 t4
              | (_ as w) -> w
          end
        | (Ttup(ts1), Ttup(ts2)) -> 
            if List.length ts1 = List.length ts2 then
              check_equal_with_withness_lists d ts1 ts2
            else 
              CEW_type (t1, t2)
        | (Tapp(args1,p1), Tapp(args2,p2)) ->
            if Path.compare p1 p2 = 0 && List.length args1 = List.length args2 then
              check_equal_with_withness_lists d args1 args2
            else
              CEW_type (t1, t2)
        | (Tne(n1),Tne(n2)) -> check_equal_with_withness_nexp n1 n2
        | _ ->  CEW_type (t1, t2)

and check_equal_with_withness_lists d ts1 ts2 =
  match (ts1, ts2) with
    | ([], _) -> CEW_equal
    | (_, []) -> CEW_equal
    | (t1::ts1', t2::ts2') ->
         match check_equal_with_withness d t1 t2 with
           | CEW_equal -> check_equal_with_withness_lists d ts1' ts2'
           | (_ as wit) -> wit

and check_equal_with_withness_nexp n1 n2 =
  if n1 == n2 then CEW_equal
  else let n1 = normalize n1 in
       let n2 = normalize n2 in
       check_equal_with_withness_nexp_help n1 n2

and check_equal_with_withness_nexp_help n1 n2 =
  match (n1.nexp,n2.nexp) with
    | (Nuvar _ , _ ) -> CEW_nexp (n1, n2)
    | (_ , Nuvar _ ) -> CEW_nexp (n1, n2)
    | (Nvar(s1),Nvar(s2)) ->
        if Nvar.compare s1 s2 = 0 then
          CEW_equal
        else CEW_nexp (n1, n2)
    | (Nconst(i),Nconst(j)) -> if i = j then CEW_equal else CEW_nexp (n1, n2)
    | (Nadd(n11,n12),Nadd(n21,n22)) | (Nmult(n11,n12),Nmult(n21,n22)) -> begin
       match check_equal_with_withness_nexp n11 n21 with
         | CEW_equal -> check_equal_with_withness_nexp n12 n22
         | (_ as wit) -> wit
      end
    | (Nneg(n1),Nneg(n2)) -> check_equal_with_withness_nexp n1 n2
    | _ -> CEW_nexp (n1, n2)


let assert_equal l m (d : type_defs) (t1 : t) (t2 : t) : unit =
  match check_equal_with_withness d t1 t2 with
    | CEW_equal -> ()
    | CEW_type (t1', t2') -> type_mismatch l m t1' t2'
    | CEW_nexp (n1, n2) -> nexp_mismatch l n1 n2


let check_equal (d : type_defs) (t1 : t) (t2 : t) : bool =
  match check_equal_with_withness d t1 t2 with
    | CEW_equal -> true
    | _ -> false

let compare_expand (d : type_defs) (t1 : t) (t2 : t) : int =
  match check_equal_with_withness d t1 t2 with
    | CEW_equal -> 0
    | CEW_type (t1', t2') -> compare t1' t2'
    | CEW_nexp (n1, n2) -> compare_nexp n1 n2


let rec nexp_from_list nls = match nls with
    | [] -> assert false
    | [n] -> n
    | [n1;n2] -> {nexp = Nadd(n1,n2)}
    | n1::nls -> {nexp = Nadd(n1,(nexp_from_list nls))}

let range_of_n = function
  | LtEq(_,n) | Eq(_,n) | GtEq(_,n) -> n
let range_l = function
  | LtEq(l,_) | Eq(l,_) | GtEq(l,_) -> l

let mk_gt_than l n1 n2 =
  let n = normalize {nexp = Nadd(n1, {nexp = Nneg n2}) } in
  GtEq(l,n)

let mk_eq_to l n1 n2 =
  let n = normalize {nexp = Nadd(n1,{nexp = Nneg n2}) } in
  Eq(l,n)

let range_with r n = match r with
  | LtEq(l,_) -> LtEq(l,n)
  | Eq(l,_) -> Eq(l,n)
  | GtEq(l,_) -> GtEq(l,n)

type typ_constraints = Tconstraints of TNset.t * (Path.t * tnvar) list * range list

module type Constraint = sig
  val new_type : unit -> t
  val new_nexp : unit -> nexp
  val equate_types : Ast.l -> string -> t -> t -> unit
  val in_range : Ast.l -> nexp -> nexp -> unit
  val add_constraint : Path.t -> t -> unit
  val add_length_constraint : range -> unit
  (*
  val equate_type_lists : Ast.l -> t list -> t list -> unit
   *)
  val add_tyvar : Tyvar.t -> unit 
  val add_nvar : Nvar.t -> unit
  (*
  val same_types : Ast.l -> t list -> t
  val dest_fn_type : Ast.l -> t -> t * t
   *)
  val inst_leftover_uvars : Ast.l -> typ_constraints
  val check_numeric_constraint_implication : Ast.l -> range -> range list -> unit
end

module type Global_defs = sig
  val d : type_defs 
  val i : (instance list) Pfmap.t 
end 

module Constraint (T : Global_defs) : Constraint = struct

  let next_uvar : int ref = ref 0
  let uvars : t list ref = ref []
  let tvars : TNset.t ref = ref TNset.empty

  let next_nuvar : int ref = ref 0
  let nuvars : nexp list ref = ref []
  let nvars : TNset.t ref = ref TNset.empty

  let class_constraints : (Path.t * t) list ref = ref []
  let length_constraints : range list ref = ref []

  let add_length_constraint r =
(*   let _ = fprintf std_formatter "adding constraint %a \n" pp_range r in *)
   length_constraints := r :: (!length_constraints)

  let new_type () : t =
    let i = !(next_uvar) in
      incr next_uvar;
      let t = { t = Tuvar({ index=i; subst=None }); } in
        uvars := t::!uvars;
        t

  let new_nexp () : nexp =
    let i = !(next_nuvar) in
      incr next_nuvar;
      let n = { nexp = Nuvar({ nindex = i; nsubst=None }); } in
        nuvars := n::!nuvars;
        n

  let add_tyvar (tv : Tyvar.t) : unit =
    tvars := TNset.add (Ty tv) (!tvars)

  let add_nvar (nv : Nvar.t) : unit = 
    nvars := TNset.add (Nv nv) (!nvars)

  let rec occurs_check (t_box : t) (t : t) : unit =
    let t = resolve_subst t in
      if t_box == t then
        raise (err_type Ast.Unknown "Failed occurs check")
      else
        match t.t with
          | Tfn(t1,t2) ->
              occurs_check t_box t1;
              occurs_check t_box t2
          | Ttup(ts) ->
              List.iter (occurs_check t_box) ts
          | Tapp(ts,_) ->
              List.iter (occurs_check t_box) ts
          | _ -> ()

  let rec occurs_nexp_check (n_box : nexp) (n : nexp) : unit =
     let n = resolve_nexp_subst n in 
       if n_box == n then
          raise (err_type Ast.Unknown "Nexpressions failed occurs check")
       else
          match n.nexp with
            | Nadd(n1,n2) | Nmult(n1,n2) -> 
                occurs_nexp_check n_box n1;
                occurs_nexp_check n_box n2;
            | Nneg(n) -> occurs_nexp_check n_box n;
            | _ -> ()

  let prim_equate_types (t_box : t) (t : t) : unit =
    let t = resolve_subst t in
      if t_box == t then
        ()
      else
        (occurs_check t_box t;
         match t.t with
           | Tuvar(_) ->
               (match t_box.t with
                  | Tuvar(u) ->
                      u.subst <- Some(t)
                  | _ ->
                      assert false)
           | _ ->
               t_box.t <- t.t)

  let rec equate_types (l : Ast.l) m (t1 : t) (t2 : t) : unit =
    if t1 == t2 then
      ()
    else
    let t1 = head_norm T.d t1 in
    let t2 = head_norm T.d t2 in
      match (t1.t,t2.t) with
        | (Tuvar _, _) -> 
            prim_equate_types t1 t2
        | (_, Tuvar _) -> 
            prim_equate_types t2 t1
        | (Tvar(s1), Tvar(s2)) ->
            if Tyvar.compare s1 s2 = 0 then
              ()
            else
              type_mismatch l m t1 t2
        | (Tfn(t1,t2), Tfn(t3,t4)) ->
            equate_types l m t1 t3;
            equate_types l m t2 t4
        | (Ttup(ts1), Ttup(ts2)) -> 
            if List.length ts1 = List.length ts2 then
              equate_type_lists l m ts1 ts2
            else 
              type_mismatch l m t1 t2
        | (Tapp(args1,p1), Tapp(args2,p2)) ->
            if Path.compare p1 p2 = 0 && List.length args1 = List.length args2 then
              equate_type_lists l m args1 args2
            else
              type_mismatch l m t1 t2
        | (Tne(n1),Tne(n2)) ->
           equate_nexps l n1 n2;
        | _ -> 
            type_mismatch l m t1 t2

  and equate_type_lists l m ts1 ts2 =
    List.iter2 (equate_types l m) ts1 ts2

  (* Should go *)
  and prim_equate_nexps (n_box : nexp) (n : nexp) : unit =
    let n = resolve_nexp_subst n in 
      if n_box == n then
        ()
      else
        (occurs_nexp_check n_box n; 
         match n.nexp with
           | Nuvar(_) ->
               (match n_box.nexp with
                  | Nuvar(u) ->
                      u.nsubst <- Some(n)
                  | _ ->
                      assert false)
           | _ ->
               n_box.nexp <- n.nexp)

  (*Should go*)
  and equate_nexps_help l nexp1 nexp2 =
     match (nexp1.nexp,nexp2.nexp) with
       | (Nuvar _, _) -> prim_equate_nexps nexp1 nexp2
       | (_, Nuvar _) -> prim_equate_nexps nexp2 nexp1
       | Nvar(nv1),Nvar(nv2) -> if (Nvar.compare nv1 nv2) = 0 then () else nexp_mismatch l nexp1 nexp2
       | Nconst(i),Nconst(j) -> if i=j then () else nexp_mismatch l nexp1 nexp2
       | Nmult(nl1,nl2),Nmult(nr1,nr2) | Nadd(nl1,nl2),Nadd(nr1,nr2) ->
           equate_nexps_help l nl1 nr1;
           equate_nexps_help l nl2 nr2;
       | (Nneg(n1),Nneg(n2)) -> equate_nexps_help l n1 n2;
       | _ -> nexp_mismatch l nexp1 nexp2

  and equate_nexps l nexp1 nexp2 =
    if nexp1 == nexp2
      then ()
    else 
      let n1 = normalize nexp1 in
      let n2 = normalize nexp2 in
      let n3 = normalize { nexp = Nadd(n1, {nexp= Nneg n2}) } in
(*      let _ = fprintf std_formatter "equate nexps of n1 %a n2 %a and diff %a \n" pp_nexp n1 pp_nexp n2 pp_nexp n3 in *)
      match n3.nexp with
       | Nconst 0 -> ()
       | _ -> add_length_constraint (Eq (l,n3))
       
  let in_range l vec_n n =
    let (top,bot) = (normalize vec_n,normalize n) in
    let bound = normalize {nexp = Nadd(top, {nexp = Nneg(bot)})} in
(*    let _ = fprintf std_formatter "in_range of %a and %a, with diff %a\n" pp_nexp top pp_nexp bot pp_nexp bound in *)
    match bound.nexp with
     | Nconst i -> if (i >= 0) then () else nexp_mismatch l top bot (* TODO make this bound not matching*)
     | _ -> add_length_constraint (GtEq(l,bound))

(*
  let equate_types l t1 t2 =
    fprintf std_formatter "%a@ =@ %a@\n"
      pp_type t1
      pp_type t2;
    equate_types l t1 t2;
    fprintf std_formatter "%a@ =@ %a@\n@\n"
      pp_type t1
      pp_type t2
 *)

  let add_constraint p t =
(*  let _ = fprintf std_formatter "adding constraint %a@ \n" pp_instance_constraint (p,t) in *)
    class_constraints := (p,t) :: (!class_constraints)

  let cur_tyvar = ref 0

  let rec get_next_tvar (i : int) : (int * tnvar) =
    let tv = Ty (Tyvar.nth i) in
      if TNset.mem tv (!tvars) then
        get_next_tvar (i + 1) 
      else
        (i,tv)

  let next_tyvar () : tnvar =
    let (i,tv) = get_next_tvar !cur_tyvar in
      cur_tyvar := i+1;
      tv

  let cur_nvar = ref 0

  let rec get_next_nvar (i : int) : (int * tnvar) =
    let nv = Nv (Nvar.nth i) in
      if TNset.mem nv (!nvars) then
         get_next_nvar (i + 1)
      else
         (i,nv)

  let next_nvar () : tnvar =
    let (i,nv) = get_next_nvar !cur_nvar in
      cur_nvar := i+1;
      nv

  (* Gather all variables and unification variables used within a set of length constraints *)
  let collect_vars (constraints : range list) : nexp list =
   let rec insert v = function
   | [] -> [v]
   | vo::vars -> begin match (compare_nexp v vo) with
                 | -1 -> vo::(insert v vars)
                 |  0 -> v::vars
                 |  _ -> v::(vo::vars)
                 end
   in
   let rec add_vars curr_vars n = match n.nexp with
    | Nvar _ | Nuvar _ -> insert n curr_vars
    | Nconst _ -> curr_vars
    | Nmult(n1,n2) -> add_vars curr_vars n1 (* Due to normalize, n2 is const *)
    | Nadd(n1,n2) -> add_vars (add_vars curr_vars n2) n1
    | _ -> assert false (*Due to normalize, should not happen*)
   in   
   let rec walk_constraints curr_vars = function
   | [ ] -> curr_vars
   | c::constraints -> 
(*     let _ = fprintf std_formatter "calling collect_vars of %a@ \n" pp_range c in *)
     walk_constraints (add_vars curr_vars (range_of_n c)) constraints
   in
   walk_constraints [] constraints

  (* Make sure that each constraint contains all variables of the set of constraints and put each "row" into an array *)
  let expand_matrix constraints all_vars =
    (* Add a multiply by 0 term so that all variables are present in all terms *)
    let zero = { nexp = Nconst 0 } in
    let mult_zero v = { nexp = Nmult(v, zero ) } in
    let get_var n = match n.nexp with 
       | Nuvar _  | Nvar _ -> n
       | Nmult(n,_) -> n
       | _ -> assert false
    in
    let rec add_vars all_vars n =
      match (all_vars,n.nexp) with
       | ([],_) -> n
       | (var::all_vars, Nconst _) -> add_vars all_vars { nexp = Nadd(n, mult_zero var) } 
       | (var::all_vars, Nuvar _ ) | (var::all_vars , Nvar _ ) | (var::all_vars, Nmult _ ) ->
          begin match (compare_nexp var (get_var n)) with
          | -1 -> add_vars all_vars { nexp = Nadd(n, mult_zero var) }
          | 0 -> add_vars all_vars n
          | _ -> add_vars all_vars { nexp = Nadd(mult_zero var, n) }
         end
       | (var::all_vars, Nadd(n1,n2)) ->
          begin match n2.nexp with 
          | Nuvar _ | Nvar _ | Nmult _ ->
            begin match (compare_nexp var (get_var n2)) with
            | -1 -> {nexp = Nadd( (add_vars all_vars n2), mult_zero var) }
            | 0 ->  add_vars all_vars n
            | _ -> { nexp = Nadd( (add_vars (var::all_vars) n1), n2) }
            end
          | _ -> assert false (*Normal so should not be reached*)
         end
       | _ -> assert false (*Normal so should not be reached*)
    in
    let rec walk_constraints = function
    | [ ] -> [ ]
    | c :: constraints -> range_with c (add_vars all_vars (range_of_n c)) :: (walk_constraints  constraints)
    in 
    Array.of_list(List.map (fun r -> ref (Some r)) constraints (* (walk_constraints constraints) *))
    
  let is_inconsistent = function
    | Eq(_,n) -> (*let _ = fprintf std_formatter "inconsistent Eq call of %a@ \n" pp_nexp n in*)
                 begin match (normalize n).nexp with
                 | Nconst(i) -> not (i=0)
                 | _ -> false end
    | GtEq(_,n) -> (*let _ = fprintf std_formatter "inconsistent GtEq call of %a@ \n" pp_nexp n in*)
                   begin match (normalize n).nexp with
                   | Nconst(i) -> i<0
                   | _ -> false end
    | LtEq(_,n) -> begin match (normalize n).nexp with
                   | Nconst(i) -> i>0
                   | _ -> false end

  let is_redundant = function
    | Eq(_,n) -> begin match (normalize n).nexp with
                 | Nconst(i) -> i=0
                 | _ -> false end
    | GtEq(_,n) -> begin match (normalize n).nexp with
                   | Nconst(i) -> i>=0
                   | Nvar _ | Nuvar _ -> true (*Since all instantiations of variables must be positive in specifications *)
                   | _ -> false end
    | LtEq(_,n) -> begin match (normalize n).nexp with
                   | Nconst(i) -> i<=0
                   | _ -> false end

  (* For situations with one constraint in multiple variables, attempts only to assign unification variables where possible *)
  let solve_solo r =
    let rec nexp_to_term_list n =
      match n.nexp with
      | Nadd(n1,n2) -> n2::(nexp_to_term_list n1)
      | _ -> [n] in 
    let rec get_const n = 
       match n.nexp with 
         | Nconst(i) -> i
         | Nmult(_,n1) -> get_const n1
         | Nvar _ | Nuvar _ -> 1
         | _ -> 0 in
    let compare_nexp_consts n1 n2 = Pervasives.compare (abs (get_const n1)) (abs (get_const n2)) in
    let rec equiv_nexp_consts n1 n2 = (abs (get_const n1)) = (abs (get_const n2)) in
    let rec split_equiv_to n equivs = function
     | [] -> equivs,[]
     | n1::ns -> if (equiv_nexp_consts n1 n) 
                    then split_equiv_to n (n1::equivs) ns
                    else equivs, n1::ns
    in
    let rec assign_nuvar n1 n2 =
      match n1.nexp,n2.nexp with
      | Nvar _ , Nuvar _ -> n2.nexp <- n1.nexp
      | Nuvar _ , Nvar _ -> n1.nexp <- n2.nexp
      | Nconst _ , Nuvar _ -> n2.nexp <- Nconst(1)
      | Nuvar _ , Nconst _ -> n1.nexp <- Nconst(1)
      | Nmult(n1,_), Nmult(n2,_) -> assign_nuvar n1 n2
      | Nmult(n1,_), _ -> assign_nuvar n1 n2
      | _, Nmult(n2,_) -> assign_nuvar n1 n2
      | _ -> () in
    let rec remove_nuvars op = function
      | [] -> ()
      | n1::ns ->let equivs,ns = split_equiv_to n1 [] ns in
                 (match equivs with
                 | [] -> ()
                 | [n2] -> if (op ((get_const n1) + (get_const n2)) 0) 
                              then begin assign_nuvar n1 n2; remove_nuvars op ns end
                              else remove_nuvars op ns
                 | _ -> remove_nuvars op ns) in
(*    let _ = fprintf std_formatter "solving solo of %a\n" pp_range r in *)
    let scp n1 n2 = () (*fprintf std_formatter "special case after solve, %a %a\n" pp_nexp n1 pp_nexp n2 *) in 
    match r with
    | Eq(l,n) -> let terms = List.sort compare_nexp_consts (nexp_to_term_list n) in
                 remove_nuvars (=) terms;
                 let n = normalize n in
                (match n.nexp with
                 | Nconst 0 -> None
                 | Nadd(n1,n2) -> (match n1.nexp,n2.nexp with
                                    | Nconst(i),Nuvar _ -> begin (scp n1 n2); n2.nexp <- Nconst( i * -1); (scp n1 n2); None end
                                    | Nconst(i),Nmult(v,c) -> (match v.nexp,c.nexp with 
                                                                 | Nuvar _ , Nconst j -> begin (scp n1 n2); v.nexp <- Nconst(i/( - j)); (scp n1 n2); None end
                                                                 | _ -> Some(Eq(l,n)))
                                    | Nvar _ ,Nuvar _ -> begin (scp n1 n2); n2.nexp <- n1.nexp; (scp n1 n2); None end
                                    | Nvar _ ,Nmult(v,c) -> (match v.nexp,c.nexp with 
                                                                 | Nuvar _ , (Nconst 1 | Nconst -1) -> begin (scp n1 n2); v.nexp <- n1.nexp; (scp n1 n2); None end
                                                                 | _ -> Some(Eq(l,n)))
                                    | Nuvar _ , Nmult(v,c) -> (match v.nexp,c.nexp with
                                                                 | Nuvar _ , Nconst -1 -> begin (scp n1 n2); v.nexp <- n1.nexp; (scp n1 n2); None end
                                                                 | _ -> Some(Eq(l,n)))
                                    | Nmult(v,c), Nuvar _ -> (match v.nexp,c.nexp with
                                                                 | Nuvar _ , Nconst -1 -> begin (scp n1 n2); n2.nexp <- v.nexp; (scp n1 n2); None end
                                                                 | _ -> Some(Eq(l,n)))

                                    | _ -> Some(Eq(l,n)))
                     | _ -> Some(Eq(l,n)))
    | GtEq(l,n) -> let n = normalize n in
                   if is_redundant(GtEq(l,n)) then None
                      else Some(GtEq(l,n))
    | LtEq(l,n) -> let n = normalize n in
                   if is_redundant(LtEq(l,n)) then None
                       else Some(LtEq(l,n))

  (*Return the nexp constant that is the multiplier for variable or unification variable v in n *)
  let rec find_multiplier v n = 
   match n.nexp with 
   | Nvar _ | Nuvar _ -> if (compare_nexp v n) = 0
                            then Some({nexp = Nconst 1})
                            else None
   | Nmult(v1,n) -> if (compare_nexp v1 v) = 0
                       then Some n
                       else None
   | Nadd(n1,n2) -> (match (find_multiplier v n2) with
                      | Some(n) -> Some n
                      | None -> find_multiplier v n2)
   | _ -> None

  (*Perform multiplications and subtractions to turn the multiplier for v to 0 in n2 while keeping n1 fixed *)
  let var_to_zero v c n1 n2 =
(*    let _ = fprintf std_formatter "var to zero call of %a@ %a@ %a@ %a@ \n" pp_nexp v pp_nexp c pp_nexp n1 pp_nexp n2 in *)
    let n2_c = find_multiplier v n2 in
    match n2_c with
      | None -> n2 (*v is already 0 in n2*)
      | Some n2_c -> normalize {nexp = Nadd({nexp = Nmult(c,n2)},{nexp = Nneg {nexp = Nmult(n2_c,n1)}})}

  let rec pivot_var n =
    match n.nexp with
     | Nvar _ | Nuvar _ -> Some(n,{nexp= Nconst 1})
     | Nmult(v,n1) -> (match n1.nexp with
                       | Nconst 0 -> None
                       | _ -> Some(v,n1))
     | Nadd(n1,n2) ->
       (match (pivot_var n2) with
         | Some(v,n) -> Some(v,n)
         | None -> pivot_var n1)
     | _ -> None

  let rec resolve_matrix i ns =
    if i >= Array.length ns 
       then ()
       else match !(ns.(i)) with
         | None -> resolve_matrix (i+1) ns
         | Some(rnge) ->
            let n = range_of_n rnge in
(*            let _ = fprintf std_formatter "resolve_matrix of %a@ \n" pp_nexp n in *)
            let potential_pivot = pivot_var n in
            match potential_pivot with 
             | None -> if (is_redundant rnge) then
                          begin ns.(i) := None ; resolve_matrix (i+1) ns end
                          else if (is_inconsistent rnge) then
                                  inconsistent_constraints rnge (range_l rnge)
                                  else resolve_matrix (i+1) ns
             | Some(v,c) -> 
               let rec inner_loop j =
                 if (j >= Array.length ns)
                   then resolve_matrix (i+1) ns
                 else if (i = j) then inner_loop (j+1)
                   else 
                     match !(ns.(j)) with
                      | None -> inner_loop (j+1)
                      | Some(rnge_j) -> 
                          let rnge_new = range_with rnge_j (var_to_zero v c n (range_of_n rnge_j)) in
(*                          let _ = fprintf std_formatter "%a@ after var_to_zero of %a and %a \n" pp_range rnge_new pp_nexp n pp_nexp (range_of_n rnge_j) in *)
                          ns.(j) := Some(rnge_new);
                          inner_loop (j+1)
                in inner_loop 0
                          
  (*TODO find where this should have come from, or move to util*)
  let rec some_list = function
    | [] -> []
    | Some(a)::rest -> (*let _ = fprintf std_formatter "some constraint %a \n" pp_range a in*)
                       a::(some_list rest)
    | None::rest -> some_list rest

  let prune_constraints rns =    
    let rec matrix_to_list i=
      if (i >= Array.length rns)
         then []
         else match !(rns.(i)) with
              | None -> matrix_to_list (i+1)
              | Some r -> r::(matrix_to_list (i+1))
    in 
    let rec combine_eq_constraints base_eq ineqs = function
      | [] -> base_eq, ineqs
      | Eq(l,n)::rns -> let eqr,ineqs = combine_eq_constraints base_eq ineqs rns in
                        Eq(l,{nexp = Nadd(n,(range_of_n eqr))}) (*location list might be better here?*) , ineqs
      | r::rns -> combine_eq_constraints base_eq (r::ineqs) rns
    in
    let lst_constraints = matrix_to_list 0 in
(*    let _ = List.iter (fun r -> fprintf std_formatter "Constraints after matrix %a\n" pp_range r) lst_constraints in *)
    let simplified_normalized_constraints = List.map solve_solo lst_constraints in
    let eq, ineqs = combine_eq_constraints (Eq(Ast.Unknown,{nexp=Nconst 0})) [] (some_list simplified_normalized_constraints) in
    let eq_normal = range_with eq (normalize (range_of_n eq)) in
    if (is_redundant eq_normal)
       then ineqs
       else eq_normal::ineqs

  let solve_numeric_constraints unresolved = function
    | [] -> unresolved
    | [c] -> (match (solve_solo c) with
              | Some(range) -> range::unresolved
              | None -> unresolved)
    | cs -> let cs = List.map (fun r -> range_with r (normalize (range_of_n r))) (some_list (List.map solve_solo cs)) in
(*            let _ = List.iter (fun r -> fprintf std_formatter "Constraint to be solved after solo %a\n" pp_range r) cs in *)
            let variables = collect_vars cs in
            let matrix = expand_matrix cs variables in
            resolve_matrix 0 matrix;
            let unresolved = prune_constraints matrix in
(*            let _ = List.iter (fun r -> fprintf std_formatter "Constraint to be kept %a\n" pp_range r) unresolved in*)
            unresolved

  let check_numeric_constraint_implication l c constraints =
    let negate_c = match c with 
                    | Eq(l,n) -> Eq(l,{nexp=Nadd(n,{nexp=Nconst 1})})
                    | GtEq(l,n) -> LtEq(l,{nexp=Nadd(n,{nexp=Nconst 1})})
                    | LtEq(l,n) -> GtEq(l,{nexp=Nadd(n,{nexp=Nconst(-1)})}) in
    if (try ignore(solve_numeric_constraints [] (negate_c::constraints));
            false
        with 
          | (Fatal_error (Err_type _)) -> true
          | e -> raise e)
       then ()
       else raise (err_type l ("Constraint " ^ range_to_string c ^ " is required by let definition but not implied by val specification\n"))

  let rec solve_constraints (instances : (instance list) Pfmap.t) (unsolvable : PTset.t) = function
    | [] -> unsolvable 
    | (p,t) :: constraints ->
        match get_matching_instance T.d (p,t) instances with
          | None ->
              solve_constraints instances (PTset.add (p,t) unsolvable) constraints
          | Some(i,subst) ->
               (** apply subst to constraints of instance *)
               let new_cs = List.map (fun (p, tnv) -> (p, 
                     match TNfmap.apply subst tnv with
                             | Some(t) -> t
                             | None -> raise (Reporting_basic.err_unreachable true i.inst_l "get_matching_instance does not provide proper substitution!")))
                    i.inst_constraints
              in
              solve_constraints instances unsolvable (new_cs @ constraints)

  let check_constraint l (p,t) =
    match t.t with
      | Tvar(tv) -> (p,Ty tv)
      | Tne(n) -> (match n.nexp with
                   | Nvar(nv) -> (p, Nv nv)
                   | _ -> let t1 = Pp.pp_to_string (fun ppf -> pp_instance_constraint ppf (p, t)) in
                      raise (err_type l ("unsatisfied type class constraint:\n    " ^t1)))
      | _ -> 
          let t1 = 
            Pp.pp_to_string (fun ppf -> pp_instance_constraint ppf (p, t))
          in 
            raise (err_type l ("unsatisfied type class constraint:\n    " ^ t1))

  let inst_leftover_uvars l =  
    let used_tvs = ref TNset.empty in
    let inst t =
      let t' = resolve_subst t in
        match t'.t with
          | Tuvar(u) ->
              let nt = next_tyvar () in
                used_tvs := TNset.add nt !used_tvs;
                t'.t <- (match nt with | Ty nt -> Tvar(nt) | _ -> assert false);
                ignore (resolve_subst t)
          | _ -> ()
    in
    let used_nvs = ref TNset.empty in
    let inst_n n = 
      let n' = resolve_nexp_subst n in
        match n'.nexp with
          | Nuvar(u) ->
             let nn = next_nvar () in
               used_nvs := TNset.add nn !used_nvs;
               n'.nexp <- (match nn with | Nv nn -> Nvar(nn) | _ -> assert false);
               ignore (resolve_nexp_subst n)
          | _ -> ()
    in
      let ns = solve_numeric_constraints [] !length_constraints in
      List.iter inst (!uvars);
      List.iter inst_n (!nuvars);
      let cs = solve_constraints T.i PTset.empty !class_constraints in
        Tconstraints(TNset.union (TNset.union !tvars !used_tvs) 
                                 (TNset.union !nvars !used_nvs), 
                     List.map (check_constraint l) (PTset.elements cs),
                     ns)
end

let rec ftvs (ts : t list) (acc : TNset.t) : TNset.t = match ts with
  | [] -> acc
  | t::ts -> ftvs ts (ftv t acc)
and ftv (t : t) (acc : TNset.t) : TNset.t = match t.t with
  | Tvar(x) -> 
      TNset.add (Ty x) acc
  | Tfn(t1,t2) -> 
      ftv t2 (ftv t1 acc)
  | Ttup(ts) -> 
      ftvs ts acc
  | Tapp(ts,_) ->
      ftvs ts acc
  | Tne(n) -> fnv n acc
  | Tuvar(_) -> 
      acc
and fnv (n:nexp) (acc : TNset.t) : TNset.t = match n.nexp with
  | Nvar(x) ->
     TNset.add (Nv x) acc
  | Nadd(n1,n2) | Nmult(n1,n2) -> fnv n1 (fnv n2 acc)
  | Nneg(n) -> fnv n acc
  | Nconst _ | Nuvar _ -> acc

