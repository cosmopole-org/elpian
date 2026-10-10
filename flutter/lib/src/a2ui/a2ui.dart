/// Elpian's A2UI v0.9.1 renderer for Flutter — a port of the web reference
/// implementation (`native/web/src/a2ui`), same module split and tests:
///
///   pointer / data_model   JSON Pointers and the surface data model
///   expressions            the `formatString` template language
///   functions / catalog    the basic catalog's functions and component table
///   context                dynamic values, checks and actions in a data scope
///   validator              message schema + component-graph validation
///   processor              surfaces from server-to-client messages
///   lowering / markdown    a surface → Elpian nodes
///   accessibility          per-component semantics
///   transport              the NDJSON agent stream
///   conversation           processor + transport + transcript for one agent
///   elpian                 the A2UISurface widget, registry and host APIs
library;

export 'errors.dart';
export 'pointer.dart';
export 'data_model.dart';
export 'expressions.dart';
export 'functions.dart';
export 'catalog.dart';
export 'context.dart';
export 'validator.dart';
export 'processor.dart';
export 'markdown.dart';
export 'lowering.dart';
export 'transport.dart';
export 'conversation.dart';
export 'elpian.dart';
export 'accessibility.dart';
