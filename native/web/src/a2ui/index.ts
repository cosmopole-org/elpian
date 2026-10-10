/**
 * Elpian's A2UI v0.9.1 renderer — the reference implementation the Flutter,
 * Android and iOS renderers port (same module split, names and tests):
 *
 *   pointer / data-model   JSON Pointers and the surface data model
 *   expressions            the `formatString` template language
 *   functions / catalog    the basic catalog's functions and component table
 *   context                dynamic values, checks and actions in a data scope
 *   validator              message schema + component-graph validation
 *   processor              surfaces from server-to-client messages
 *   lowering / markdown    a surface → Elpian nodes
 *   accessibility          per-component semantics
 *   transport              the NDJSON agent stream
 *   conversation           processor + transport + transcript for one agent
 *   elpian                 the A2UISurface widget, registry and host APIs
 */
export * from './errors.js';
export * from './pointer.js';
export * from './data-model.js';
export * from './expressions.js';
export * from './functions.js';
export * from './catalog.js';
export * from './context.js';
export * from './validator.js';
export * from './processor.js';
export * from './markdown.js';
export * from './lowering.js';
export * from './accessibility.js';
export * from './transport.js';
export * from './conversation.js';
export * from './elpian.js';
