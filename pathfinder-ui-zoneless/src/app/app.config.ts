import { ApplicationConfig, provideExperimentalZonelessChangeDetection, ErrorHandler } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withFetch } from '@angular/common/http';
import { GlobalErrorHandler } from './global-error-handler';

import { routes } from './app.routes';

export const appConfig: ApplicationConfig = {
  providers: [
    provideExperimentalZonelessChangeDetection(),
    provideRouter(routes),
    provideHttpClient(withFetch()),
    { provide: ErrorHandler, useClass: GlobalErrorHandler },
  ]
};
