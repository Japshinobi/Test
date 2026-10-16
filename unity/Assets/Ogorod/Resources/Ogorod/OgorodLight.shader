// The colour of daylight multiplied over the whole picture (warm in the morning, blue at night).
Shader "Ogorod/Light"
{
    Properties { _Color ("Light colour", Color) = (1, 1, 1, 1) }
    SubShader
    {
        Tags { "Queue" = "Overlay" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Pass
        {
            ZWrite Off ZTest Always Cull Off
            Blend DstColor Zero
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            fixed4 _Color;
            float4 vert (float4 v : POSITION) : SV_POSITION { return UnityObjectToClipPos(v); }
            fixed4 frag () : SV_Target { return fixed4(_Color.rgb, 1); }
            ENDCG
        }
    }
}
