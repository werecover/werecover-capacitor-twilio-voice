declare module "@capacitor/core" {
  interface PluginRegistry {
    TwilioVoicePlugin: TwilioVoicePluginPlugin;
  }
}

export interface TwilioVoicePluginPlugin {
  echo(options: { value: string }): Promise<{value: string}>;
}
