export type ServerConfig = {
  python_path: string;
  library_root: string;
  repkg_path: string;
  ffmpeg_path: string;
  api_host: string;
  api_port: number;
  api_username: string;
  api_password: string;
  public_api_base_url: string;
  public_static_base_url: string;
  miniserve_path: string;
  miniserve_port: number;
  miniserve_auth: string;
};

export type ProcessState = {
  running: boolean;
  label: string;
};

export type PreviewItem = {
  id: string;
  title: string;
  type: string;
  thumbnailPath: string;
  assetCount: number;
  hasPackage: boolean;
  isUnpacked: boolean;
};

export type PreviewResult = {
  ok: boolean;
  count: number;
  manifestPath: string;
  items: PreviewItem[];
};
