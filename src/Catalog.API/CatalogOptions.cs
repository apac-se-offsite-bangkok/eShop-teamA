namespace eShop.Catalog.API;

public class CatalogOptions
{
    public string? PicBaseUrl { get; set; }
    public bool UseCustomizationData { get; set; }
    
    /// <summary>
    /// Maximum number of items to return in a single page.
    /// Default value is 100.
    /// </summary>
    public int MaxPageSize { get; set; } = 100;
}
