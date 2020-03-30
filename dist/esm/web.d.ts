import { WebPlugin } from '@capacitor/core';
import { TwilioVoicePluginPlugin } from './definitions';
export declare class TwilioVoicePluginWeb extends WebPlugin implements TwilioVoicePluginPlugin {
    constructor();
    echo(options: {
        value: string;
    }): Promise<{
        value: string;
    }>;
}
declare const TwilioVoicePlugin: TwilioVoicePluginWeb;
export { TwilioVoicePlugin };
