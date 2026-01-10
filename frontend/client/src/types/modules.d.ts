// Type declarations for npm modules that may not be installed yet
// These allow TypeScript to compile even if the modules are missing at runtime

declare module 'react-markdown' {
  import { ComponentType, ReactNode } from 'react';

  interface ReactMarkdownProps {
    children: string;
    className?: string;
    components?: Record<string, ComponentType<any>>;
    remarkPlugins?: any[];
    rehypePlugins?: any[];
  }

  const ReactMarkdown: ComponentType<ReactMarkdownProps>;
  export default ReactMarkdown;
}

declare module 'react-router-dom' {
  import { ComponentType, ReactNode } from 'react';

  export function useNavigate(): (to: string | number, options?: { replace?: boolean; state?: any }) => void;
  export function useParams<T extends Record<string, string | undefined>>(): T;
  export function useLocation(): { pathname: string; search: string; hash: string; state: any };
  export function useSearchParams(): [URLSearchParams, (params: URLSearchParams) => void];

  export const Link: ComponentType<{ to: string; children: ReactNode; className?: string; [key: string]: any }>;
  export const NavLink: ComponentType<{ to: string; children: ReactNode; className?: string | ((props: { isActive: boolean }) => string); [key: string]: any }>;
  export const Navigate: ComponentType<{ to: string; replace?: boolean; state?: any }>;
  export const Outlet: ComponentType<{}>;
  export const Routes: ComponentType<{ children: ReactNode }>;
  export const Route: ComponentType<{ path: string; element: ReactNode; children?: ReactNode }>;

  export const BrowserRouter: ComponentType<{ children: ReactNode }>;
  export const HashRouter: ComponentType<{ children: ReactNode }>;
  export const MemoryRouter: ComponentType<{ children: ReactNode; initialEntries?: string[] }>;
}

declare module 'sqlite3' {
  class Database {
    constructor(filename: string, callback?: (err: Error | null) => void);
    constructor(filename: string, mode?: number, callback?: (err: Error | null) => void);
    run(sql: string, params?: any, callback?: (err: Error | null) => void): this;
    get(sql: string, params?: any, callback?: (err: Error | null, row: any) => void): this;
    all(sql: string, params?: any, callback?: (err: Error | null, rows: any[]) => void): this;
    each(sql: string, params?: any, callback?: (err: Error | null, row: any) => void, complete?: (err: Error | null, count: number) => void): this;
    exec(sql: string, callback?: (err: Error | null) => void): this;
    prepare(sql: string, params?: any, callback?: (err: Error | null) => void): Statement;
    close(callback?: (err: Error | null) => void): void;
    serialize(callback?: () => void): void;
    parallelize(callback?: () => void): void;
    on(event: string, listener: (...args: any[]) => void): this;
  }

  class Statement {
    bind(params?: any, callback?: (err: Error | null) => void): this;
    reset(callback?: (err: Error | null) => void): this;
    finalize(callback?: (err: Error | null) => void): this;
    run(params?: any, callback?: (err: Error | null) => void): this;
    get(params?: any, callback?: (err: Error | null, row: any) => void): this;
    all(params?: any, callback?: (err: Error | null, rows: any[]) => void): this;
    each(params?: any, callback?: (err: Error | null, row: any) => void, complete?: (err: Error | null, count: number) => void): this;
  }

  const OPEN_READONLY: number;
  const OPEN_READWRITE: number;
  const OPEN_CREATE: number;
  const OPEN_SHAREDCACHE: number;
  const OPEN_PRIVATECACHE: number;
  const OPEN_URI: number;

  function verbose(): typeof import('sqlite3');

  export { Database, Statement, OPEN_READONLY, OPEN_READWRITE, OPEN_CREATE, OPEN_SHAREDCACHE, OPEN_PRIVATECACHE, OPEN_URI, verbose };
}

declare module 'better-sqlite3' {
  interface Database {
    prepare(sql: string): Statement;
    exec(sql: string): this;
    transaction<T>(fn: (...args: any[]) => T): (...args: any[]) => T;
    close(): void;
    readonly open: boolean;
    readonly inTransaction: boolean;
    readonly name: string;
    readonly memory: boolean;
    readonly readonly: boolean;
  }

  interface Statement {
    run(...params: any[]): RunResult;
    get(...params: any[]): any;
    all(...params: any[]): any[];
    iterate(...params: any[]): IterableIterator<any>;
    pluck(toggle?: boolean): this;
    expand(toggle?: boolean): this;
    raw(toggle?: boolean): this;
    columns(): ColumnDefinition[];
    bind(...params: any[]): this;
  }

  interface RunResult {
    changes: number;
    lastInsertRowid: number | bigint;
  }

  interface ColumnDefinition {
    name: string;
    column: string | null;
    table: string | null;
    database: string | null;
    type: string | null;
  }

  interface DatabaseConstructor {
    new(filename: string, options?: DatabaseOptions): Database;
    (filename: string, options?: DatabaseOptions): Database;
  }

  interface DatabaseOptions {
    readonly?: boolean;
    fileMustExist?: boolean;
    timeout?: number;
    verbose?: (message?: any, ...additionalArgs: any[]) => void;
    nativeBinding?: string;
  }

  const Database: DatabaseConstructor;
  export = Database;
}
