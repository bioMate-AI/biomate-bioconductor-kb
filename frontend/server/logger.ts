/**
 * Structured Logging System
 * Provides consistent logging with levels, context, and formatting
 */

export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
}

interface LogEntry {
  level: string;
  timestamp: string;
  component: string;
  message: string;
  data?: any;
  error?: any;
}

class Logger {
  private logLevel: LogLevel;
  private component: string;

  constructor(component: string, logLevel: LogLevel = LogLevel.INFO) {
    this.component = component;
    this.logLevel = logLevel;
  }

  private shouldLog(level: LogLevel): boolean {
    return level >= this.logLevel;
  }

  private formatLog(level: string, message: string, data?: any, error?: any): LogEntry {
    return {
      level,
      timestamp: new Date().toISOString(),
      component: this.component,
      message,
      ...(data && { data }),
      ...(error && { error: this.formatError(error) }),
    };
  }

  private formatError(error: any): any {
    if (error instanceof Error) {
      return {
        name: error.name,
        message: error.message,
        stack: error.stack,
      };
    }
    return error;
  }

  private output(logEntry: LogEntry): void {
    const color = this.getColor(logEntry.level);
    const reset = '\x1b[0m';

    console.log(
      `${color}[${logEntry.timestamp}] [${logEntry.level}] [${logEntry.component}]${reset} ${logEntry.message}`
    );

    if (logEntry.data) {
      console.log('  Data:', JSON.stringify(logEntry.data, null, 2));
    }

    if (logEntry.error) {
      console.error('  Error:', logEntry.error);
    }
  }

  private getColor(level: string): string {
    switch (level) {
      case 'DEBUG': return '\x1b[36m'; // Cyan
      case 'INFO': return '\x1b[32m';  // Green
      case 'WARN': return '\x1b[33m';  // Yellow
      case 'ERROR': return '\x1b[31m'; // Red
      default: return '\x1b[0m';
    }
  }

  debug(message: string, data?: any): void {
    if (this.shouldLog(LogLevel.DEBUG)) {
      this.output(this.formatLog('DEBUG', message, data));
    }
  }

  info(message: string, data?: any): void {
    if (this.shouldLog(LogLevel.INFO)) {
      this.output(this.formatLog('INFO', message, data));
    }
  }

  warn(message: string, data?: any): void {
    if (this.shouldLog(LogLevel.WARN)) {
      this.output(this.formatLog('WARN', message, data));
    }
  }

  error(message: string, error?: any, data?: any): void {
    if (this.shouldLog(LogLevel.ERROR)) {
      this.output(this.formatLog('ERROR', message, data, error));
    }
  }

  /**
   * Log API request
   */
  request(method: string, path: string, data?: any): void {
    this.info(`${method} ${path}`, data);
  }

  /**
   * Log API response
   */
  response(method: string, path: string, status: number, duration: number): void {
    const message = `${method} ${path} ${status} in ${duration}ms`;
    if (status >= 500) {
      this.error(message);
    } else if (status >= 400) {
      this.warn(message);
    } else {
      this.info(message);
    }
  }

  /**
   * Time an operation
   */
  async time<T>(label: string, fn: () => Promise<T>): Promise<T> {
    const start = Date.now();
    try {
      const result = await fn();
      const duration = Date.now() - start;
      this.info(`${label} completed`, { duration: `${duration}ms` });
      return result;
    } catch (error) {
      const duration = Date.now() - start;
      this.error(`${label} failed`, error, { duration: `${duration}ms` });
      throw error;
    }
  }
}

// Create logger instances for different components
export const createLogger = (component: string): Logger => {
  const logLevel = process.env.LOG_LEVEL === 'debug' ? LogLevel.DEBUG : LogLevel.INFO;
  return new Logger(component, logLevel);
};

// Pre-configured loggers
export const serverLogger = createLogger('Server');
export const chatLogger = createLogger('Chat');
export const galaxyLogger = createLogger('Galaxy');
export const cacheLogger = createLogger('Cache');
