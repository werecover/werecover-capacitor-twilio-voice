import { WebPlugin } from '@capacitor/core';
import { TwilioVoicePluginPlugin } from './definitions';

export class TwilioVoicePluginWeb extends WebPlugin implements TwilioVoicePluginPlugin {
  constructor() {
    super({
      name: 'TwilioVoicePlugin',
      platforms: ['web']
    });
  }

  async echo(options: { value: string }): Promise<{value: string}> {
    console.log('ECHO', options);
    return options;
  }
}

const TwilioVoicePlugin = new TwilioVoicePluginWeb();

export { TwilioVoicePlugin };

import { registerWebPlugin } from '@capacitor/core';
registerWebPlugin(TwilioVoicePlugin);
